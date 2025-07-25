// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {VaaKey} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import {toUniversalAddress} from "wormhole-solidity-sdk/utils/UniversalAddress.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {WormholeGatewayBase} from "./WormholeGatewayBase.sol";
import {IERC7786GatewaySource} from "../../interfaces/IERC7786.sol";

// TODO: allow non-evm destination chains via non-evm-specific finalize/retry variants
abstract contract WormholeGatewaySource is IERC7786GatewaySource, WormholeGatewayBase {
    using InteroperableAddress for bytes;
    // using Strings for *;

    struct PendingMessage {
        uint64 sequence;
        address sender;
        bytes recipient;
        bytes payload;
    }

    uint256 private _sendId;
    mapping(bytes32 => PendingMessage) private _pending;

    event MessagePushed(bytes32 outboxId);
    error CannotFinalizeMessage(bytes32 outboxId);
    error CannotRetryMessage(bytes32 outboxId);
    error UnsupportedNativeTransfer();

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 /*selector*/) public pure returns (bool) {
        return false;
    }

    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(
        bytes calldata recipient, // Binary Interoperable Address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 sendId) {
        require(msg.value == 0, UnsupportedNativeTransfer());
        // Use of `if () revert` syntax to avoid accessing attributes[0] if it's empty
        if (attributes.length > 0)
            revert UnsupportedAttribute(attributes[0].length < 0x04 ? bytes4(0) : bytes4(attributes[0][0:4]));

        // Note: this reverts with UnsupportedChainId if the recipient is not on a supported chain.
        // No real need to check the return value.
        getRemoteGateway(recipient);

        sendId = bytes32(++_sendId);
        _pending[sendId] = PendingMessage(0, msg.sender, recipient, payload);

        emit MessageSent(
            sendId,
            InteroperableAddress.formatEvmV1(block.chainid, msg.sender),
            recipient,
            payload,
            0,
            attributes
        );
    }

    function quoteEvmMessage(bytes memory destinationChain, uint256 gasLimit) public view returns (uint256) {
        (uint256 cost, ) = _wormholeRelayer.quoteEVMDeliveryPrice(getWormholeChain(destinationChain), 0, gasLimit);
        return cost;
    }

    function quoteEvmMessage(bytes32 outboxId, uint256 gasLimit) external view returns (uint256) {
        return quoteEvmMessage(_pending[outboxId].recipient, gasLimit);
    }

    function finalizeEvmMessage(bytes32 outboxId, uint256 gasLimit) external payable {
        PendingMessage storage pmsg = _pending[outboxId];

        require(pmsg.sender != address(0), CannotFinalizeMessage(outboxId));

        bytes memory adapterPayload = abi.encode(
            outboxId,
            InteroperableAddress.formatEvmV1(block.chainid, pmsg.sender),
            pmsg.recipient,
            pmsg.payload
        );

        // TODO: potentially delete part/all of the message

        pmsg.sequence = _wormholeRelayer.sendPayloadToEvm{value: msg.value}(
            getWormholeChain(pmsg.recipient),
            getRemoteGateway(pmsg.recipient),
            adapterPayload,
            0,
            gasLimit
        );

        emit MessagePushed(outboxId);
    }

    // Is this necessary ? How does that work since we are not providing any additional payment ?
    // Is re-calling finalizeEvmMessage an alternative ?
    function retryEvmMessage(bytes32 outboxId, uint256 gasLimit, address newDeliveryProvider) external {
        PendingMessage storage pmsg = _pending[outboxId];

        require(pmsg.sequence != 0, CannotRetryMessage(outboxId));

        pmsg.sequence = _wormholeRelayer.resendToEvm(
            VaaKey(_wormholeChainId, toUniversalAddress(address(this)), pmsg.sequence),
            getWormholeChain(pmsg.recipient),
            0,
            gasLimit,
            newDeliveryProvider
        );
    }
}
