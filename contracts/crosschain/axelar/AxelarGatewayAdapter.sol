// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC7786GatewaySource} from "../../interfaces/IERC7786.sol";
import {IERC7786Receiver} from "../../interfaces/IERC7786.sol";

/**
 * @dev Implementation of an ERC-7786 gateway destination adapter for the Axelar Network in dual mode.
 *
 * The contract implements AxelarExecutable's {_execute} function to execute the message, converting Axelar's native
 * workflow into the standard ERC-7786.
 *
 * NOTE: While both ERC-7786 and Axelar do support non-evm chains, this adaptor does not. This limitation comes from
 * the translation of the ERC-7930 interoperable address (binary objects -- bytes) to strings. This is necessary
 * because Axelar uses string to represent addresses. For EVM network, this adapter uses a checksum hex string
 * representation. Other networks would require a different encoding. Ideally we would have a single encoding for all
 * networks (could be base58, base64, ...) but Axelar doesn't support that.
 */
// slither-disable-next-line locked-ether
contract AxelarGatewayAdapter is IERC7786GatewaySource, Ownable, AxelarExecutable {
    using InteroperableAddress for bytes;
    using Strings for *;

    // Remote gateway.
    // `addr` is the isolated address part of ERC-7930. Its not a full ERC-7930 interoperable address.
    mapping(bytes2 chainType => mapping(bytes chainReference => bytes addr)) private _remoteGateways;

    // chain equivalence ERC-7930 (no address) <> Axelar
    mapping(bytes erc7930 => string axelar) private _erc7930ToAxelar;
    mapping(string axelar => bytes erc7930) private _axelarToErc7930;

    /// @dev A remote gateway has been registered for a chain.
    event RegisteredRemoteGateway(bytes remote);

    /// @dev A chain equivalence has been registered.
    event RegisteredChainEquivalence(bytes erc7930binary, string axelar);

    error UnsupportedNativeTransfer();
    error InvalidOriginGateway(string axelarSourceChain, string axelarSourceAddress);
    error ReceiverExecutionFailed();
    error UnsupportedChainType(bytes2 chainType);
    error UnsupportedERC7930Chain(bytes erc7930binary);
    error UnsupportedAxelarChain(string axelar);
    error InvalidChainIdentifier(bytes erc7930binary);
    error ChainEquivalenceAlreadyRegistered(bytes erc7930binary, string axelar);
    error RemoteGatewayAlreadyRegistered(bytes2 chainType, bytes chainReference);

    /// @dev Initializes the contract with the Axelar gateway and the initial owner.
    constructor(
        IAxelarGateway gateway,
        address initialOwner
    ) Ownable(initialOwner) AxelarExecutable(address(gateway)) {}

    /// @dev Returns the Axelar chain identifier for a given binary interoperable chain id.
    function getAxelarChain(bytes memory input) public view virtual returns (string memory output) {
        output = _erc7930ToAxelar[input];
        require(bytes(output).length > 0, UnsupportedERC7930Chain(input));
    }

    /// @dev Returns the binary interoperable chain id for a given Axelar chain identifier.
    function getErc7930Chain(string memory input) public view virtual returns (bytes memory output) {
        output = _axelarToErc7930[input];
        require(output.length > 0, UnsupportedAxelarChain(input));
    }

    /// @dev Returns the address of the remote gateway for a given binary interoperable chain id.
    function getRemoteGateway(bytes memory chain) public view virtual returns (bytes memory) {
        (bytes2 chainType, bytes memory chainReference, ) = chain.parseV1();
        return getRemoteGateway(chainType, chainReference);
    }

    /// @dev Returns the address of the remote gateway for a given chainType and chainReference.
    function getRemoteGateway(
        bytes2 chainType,
        bytes memory chainReference
    ) public view virtual returns (bytes memory) {
        bytes memory addr = _remoteGateways[chainType][chainReference];
        if (addr.length == 0)
            revert UnsupportedERC7930Chain(InteroperableAddress.formatV1(chainType, chainReference, ""));
        return addr;
    }

    /// @dev Registers a chain equivalence between a binary interoperable chain id and an Axelar chain identifier.
    function registerChainEquivalence(bytes calldata chain, string calldata axelar) public virtual onlyOwner {
        (, , bytes calldata addr) = chain.parseV1Calldata();
        require(addr.length == 0, InvalidChainIdentifier(chain));
        require(
            bytes(_erc7930ToAxelar[chain]).length == 0 && _axelarToErc7930[axelar].length == 0,
            ChainEquivalenceAlreadyRegistered(chain, axelar)
        );

        _erc7930ToAxelar[chain] = axelar;
        _axelarToErc7930[axelar] = chain;
        emit RegisteredChainEquivalence(chain, axelar);
    }

    /// @dev Registers the address of a remote gateway.
    function registerRemoteGateway(bytes calldata remote) public virtual onlyOwner {
        (bytes2 chainType, bytes calldata chainReference, bytes calldata addr) = remote.parseV1Calldata();
        require(
            _remoteGateways[chainType][chainReference].length == 0,
            RemoteGatewayAlreadyRegistered(chainType, chainReference)
        );
        _remoteGateways[chainType][chainReference] = addr;
        emit RegisteredRemoteGateway(remote);
    }

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 /*selector*/) public pure returns (bool) {
        return false;
    }

    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(
        bytes calldata recipient, // Binary Interoperable Address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32) {
        require(msg.value == 0, UnsupportedNativeTransfer());
        // Use of `if () revert` syntax to avoid accessing attributes[0] if it's empty
        if (attributes.length > 0)
            revert UnsupportedAttribute(attributes[0].length < 0x04 ? bytes4(0) : bytes4(attributes[0][0:4]));

        // Create the package
        bytes memory sender = InteroperableAddress.formatEvmV1(block.chainid, msg.sender);
        bytes memory adapterPayload = abi.encode(sender, recipient, payload);

        // Emit event early (stack too deep)
        bytes32 sendId = bytes32(0); // Explicitly set to 0
        emit MessageSent(sendId, sender, recipient, payload, 0, attributes);

        // Send the message
        (bytes2 chainType, bytes calldata chainReference, ) = recipient.parseV1Calldata();
        bytes memory remoteGateway = getRemoteGateway(chainType, chainReference);
        string memory axelarDestination = getAxelarChain(InteroperableAddress.formatV1(chainType, chainReference, ""));
        string memory axelarTarget = _stringifyAddress(chainType, remoteGateway);

        gateway().callContract(axelarDestination, axelarTarget, adapterPayload);

        return sendId;
    }

    /**
     * @dev Execution of a cross-chain message.
     *
     * In this function:
     *
     * - `axelarSourceChain` is in the Axelar format. It should not be expected to be a proper ERC-7930 format
     * - `axelarSourceAddress` is the sender of the Axelar message. That should be the remote gateway on the chain
     *   which the message originates from. It is NOT the sender of the ERC-7786 crosschain message.
     *
     * Proper ERC-7930 encoding of the crosschain message sender can be found in the message
     */
    function _execute(
        bytes32 commandId,
        string calldata axelarSourceChain, // chain of the remote gateway - axelar format
        string calldata axelarSourceAddress, // address of the remote gateway
        bytes calldata adapterPayload
    ) internal override {
        // Parse the package
        (bytes memory sender, bytes memory recipient, bytes memory payload) = abi.decode(
            adapterPayload,
            (bytes, bytes, bytes)
        );

        // variable lifecycle: avoid stack-too-deep
        {
            // Axelar to ERC-7930 translation
            (bytes2 chainType, bytes memory chainReference, ) = getErc7930Chain(axelarSourceChain).parseV1();
            bytes memory addr = getRemoteGateway(chainType, chainReference);

            // check message validity
            // - `axelarSourceAddress` is the remote gateway on the origin chain.
            require(
                _stringifyAddress(chainType, addr).equal(axelarSourceAddress),
                InvalidOriginGateway(axelarSourceChain, axelarSourceAddress)
            );
        }

        (, address target) = recipient.parseEvmV1();
        bytes4 result = IERC7786Receiver(target).receiveMessage(commandId, sender, payload);
        require(result == IERC7786Receiver.receiveMessage.selector, ReceiverExecutionFailed());
    }

    /// @dev ERC-7930 to Axelar address translation. Currently only supports EVM chains.
    function _stringifyAddress(bytes2 chainType, bytes memory addr) internal virtual returns (string memory) {
        if (chainType == 0) {
            return address(bytes20(addr)).toChecksumHexString();
        } else {
            revert UnsupportedChainType(chainType);
        }
    }
}
