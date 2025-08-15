// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC7786GatewaySource} from "../../interfaces/IERC7786.sol";
import {IERC7786Attributes} from "../../interfaces/IERC7786Attributes.sol";
import {IERC7786Receiver} from "../../interfaces/IERC7786.sol";
import {ERC7786Attributes} from "../utils/ERC7786Attributes.sol";
import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";

/**
 * @dev Implementation of an ERC-7786 gateway destination adapter for the Axelar Network in dual mode.
 *
 * The contract implements AxelarExecutable's {_execute} function to execute the message, converting Axelar's native
 * workflow into the standard ERC-7786.
 */
contract AxelarGatewayAdaptor is IERC7786GatewaySource, AxelarGatewayBase, AxelarExecutable {
    using InteroperableAddress for bytes;
    using Strings for *;

    struct MessageDetails {
        string destination;
        string target;
        bytes payload;
    }

    uint256 private _sendId;
    mapping(bytes32 => MessageDetails) private _details;

    error UnsupportedNativeTransfer();
    error InvalidOriginGateway(string axelarSourceChain, string axelarSourceAddress);
    error ReceiverExecutionFailed();

    /// @dev Initializes the contract with the Axelar gateway and the initial owner.
    constructor(
        IAxelarGateway gateway,
        IAxelarGasService gasService,
        address initialOwner
    ) Ownable(initialOwner) AxelarGatewayBase(gateway, gasService) AxelarExecutable(address(gateway)) {}

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 selector) public pure returns (bool) {
        return selector == IERC7786Attributes.requestRelay.selector;
    }

    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(
        bytes calldata recipient, // Binary Interoperable Address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 sendId) {
        // Process attributes (relay)
        bool withRelay = false;
        uint256 value = 0;
        address refundRecipient = address(0);

        for (uint256 i = 0; i < attributes.length; ++i) {
            (withRelay, value, , refundRecipient) = ERC7786Attributes.tryDecodeRequestRelayCalldata(attributes[i]);
            require(withRelay, UnsupportedAttribute(attributes[i].length < 0x04 ? bytes4(0) : bytes4(attributes[i])));
        }
        if (!withRelay) {
            sendId = bytes32(++_sendId);
        }
        require(msg.value == value, UnsupportedNativeTransfer());

        // Create the package
        bytes memory sender = InteroperableAddress.formatEvmV1(block.chainid, msg.sender);
        bytes memory adapterPayload = abi.encode(sender, recipient, payload);

        // Emit event early (stack too deep)
        emit MessageSent(sendId, sender, recipient, payload, 0, attributes);

        // Send the message
        (bytes2 chainType, bytes calldata chainReference, ) = recipient.parseV1Calldata();
        bytes memory remoteGateway = getRemoteGateway(chainType, chainReference);
        string memory axelarDestination = getAxelarChain(InteroperableAddress.formatV1(chainType, chainReference, ""));
        string memory axelarTarget = address(bytes20(remoteGateway)).toChecksumHexString(); // TODO non-evm chains?

        _axelarGateway.callContract(axelarDestination, axelarTarget, adapterPayload);

        if (withRelay) {
            _axelarGasService.payNativeGasForContractCall{value: msg.value}(
                address(this),
                axelarDestination,
                axelarTarget,
                adapterPayload,
                refundRecipient
            );
        } else {
            _details[sendId] = MessageDetails(axelarDestination, axelarTarget, adapterPayload);
        }
    }

    // TODO inheritdoc from interface when that is standardized
    function requestRelay(bytes32 sendId, uint256 /*gasLimit*/, address refundRecipient) external payable {
        MessageDetails storage details = _details[sendId];
        require(details.payload.length > 0);

        _axelarGasService.payNativeGasForContractCall{value: msg.value}(
            address(this),
            details.destination,
            details.target,
            details.payload,
            refundRecipient
        );
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

        // Axelar to ERC-7930 translation
        bytes memory addr = getRemoteGateway(getErc7930Chain(axelarSourceChain));

        // check message validity
        // - `axelarSourceAddress` is the remote gateway on the origin chain.
        require(
            address(bytes20(addr)).toChecksumHexString().equal(axelarSourceAddress), // TODO non-evm chains?
            InvalidOriginGateway(axelarSourceChain, axelarSourceAddress)
        );

        (, address target) = recipient.parseEvmV1();
        bytes4 result = IERC7786Receiver(target).receiveMessage(commandId, sender, payload);
        require(result == IERC7786Receiver.receiveMessage.selector, ReceiverExecutionFailed());
    }
}
