// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";

/**
 * @dev Base implementation of a cross-chain gateway adapter for the Axelar Network.
 *
 * This contract allows developers to register equivalence between chains (i.e. ERC-7930 chain type and reference
 * to Axelar chain identifiers) and remote gateways (i.e. gateways on other chains) to facilitate cross-chain
 * communication.
 */
abstract contract AxelarGatewayBase is Ownable {
    using InteroperableAddress for bytes;

    /// @dev A remote gateway has been registered for a chain.
    event RegisteredRemoteGateway(bytes remote);

    /// @dev A chain equivalence has been registered.
    event RegisteredChainEquivalence(bytes erc7930binary, string axelar);

    /// @dev Error emitted when an unsupported chain is queried.
    error UnsupportedERC7930Chain(bytes erc7930binary);
    error UnsupportedAxelarChain(string axelar);
    error InvalidChainIdentifier(bytes erc7930binary);
    error ChainEquivalenceAlreadyRegistered(bytes erc7930binary, string axelar);
    error RemoteGatewayAlreadyRegistered(bytes2 chainType, bytes chainReference);

    /// @dev Axelar's official gateway for the current chain.
    IAxelarGateway internal immutable _axelarGateway;

    // Remote gateway.
    // `addr` is the isolated address part of ERC-7930. Its not a full ERC-7930 interoperable address.
    mapping(bytes2 chainType => mapping(bytes chainReference => bytes addr)) private _remoteGateways;

    // chain equivalence ERC-7930 (no address) <> Axelar
    mapping(bytes erc7930 => string axelar) private _erc7930ToAxelar;
    mapping(string axelar => bytes erc7930) private _axelarToErc7930;

    /// @dev Sets the local gateway address (i.e. Axelar's official gateway for the current chain).
    constructor(IAxelarGateway _gateway) {
        _axelarGateway = _gateway;
    }

    /// @dev Returns the equivalent chain given an id that can be either either a binary interoperable address or an Axelar network identifier.
    function getAxelarChain(bytes memory input) public view virtual returns (string memory output) {
        output = _erc7930ToAxelar[input];
        require(bytes(output).length > 0, UnsupportedERC7930Chain(input));
    }

    function getErc7930Chain(string memory input) public view virtual returns (bytes memory output) {
        output = _axelarToErc7930[input];
        require(output.length > 0, UnsupportedAxelarChain(input));
    }

    /// @dev Returns the address of the remote gateway for a given chainType and chainReference.
    function getRemoteGateway(bytes memory chain) public view virtual returns (bytes memory) {
        (bytes2 chainType, bytes memory chainReference, ) = chain.parseV1();
        return getRemoteGateway(chainType, chainReference);
    }

    function getRemoteGateway(
        bytes2 chainType,
        bytes memory chainReference
    ) public view virtual returns (bytes memory) {
        bytes memory addr = _remoteGateways[chainType][chainReference];
        if (addr.length == 0)
            revert UnsupportedERC7930Chain(InteroperableAddress.formatV1(chainType, chainReference, ""));
        return addr;
    }

    /// @dev Registers a chain equivalence between a binary interoperable address an Axelar network identifier.
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
}
