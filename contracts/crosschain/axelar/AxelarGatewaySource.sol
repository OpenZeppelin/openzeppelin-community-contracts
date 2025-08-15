// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC7786GatewaySource} from "../../interfaces/IERC7786.sol";
import {IERC7786Attributes} from "../../interfaces/IERC7786Attributes.sol";
import {ERC7786Attributes} from "../utils/ERC7786Attributes.sol";
import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";

/**
 * @dev Implementation of an ERC-7786 gateway source adapter for the Axelar Network.
 *
 * The contract provides a way to send messages to a remote chain via the Axelar Network
 * using the {sendMessage} function.
 */
abstract contract AxelarGatewaySource is IERC7786GatewaySource, AxelarGatewayBase {
    using InteroperableAddress for bytes;

    struct MessageDetails {
        string destination;
        string target;
        bytes payload;
    }

    uint256 private _lastSendId;
    mapping(bytes32 => MessageDetails) private _details;

    error UnsupportedNativeTransfer();

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
            sendId = bytes32(++_lastSendId);
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
        // TODO: How should we "stringify" addresses on non-evm chains. Axelar doesn't yet support hex format for all
        // non evm addresses. Do we want to use Hex? Base58? Base64?
        string memory axelarTarget = chainType == 0x0000
            ? Strings.toChecksumHexString(address(bytes20(remoteGateway)))
            : Strings.toHexString(remoteGateway);

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

        _axelarGateway.callContract(axelarDestination, axelarTarget, adapterPayload);
    }

    /**
     * @dev Request relaying of a message initiated using `sendMessage`.
     *
     * NOTE: AxelarGasService does NOT take a gasLimit. Instead it uses the msg.value sent to determine the gas limit.
     * This function ignores the provided `gasLimit` parameter.
     */
    function requestRelay(bytes32 sendId, uint256 /*gasLimit*/, address refundRecipient) external payable {
        MessageDetails memory details = _details[sendId];
        require(details.payload.length > 0);

        // delete storage for some refund
        delete _details[sendId];

        _axelarGasService.payNativeGasForContractCall{value: msg.value}(
            address(this),
            details.destination,
            details.target,
            details.payload,
            refundRecipient
        );
    }
}
