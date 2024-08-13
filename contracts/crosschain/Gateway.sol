// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IGatewayDestination, IGatewaySource, IGateway} from "./IGateway.sol";
import {Set} from "../utils/Set.sol";

/// @dev Generic implementation of a Gateway contract on the source chain according to ERC-XXXX definitions.
abstract contract GatewaySource is IGatewaySource {
    using Set for Set.Bytes32Set;
    Set.Bytes32Set private _createdBox;
    Set.Bytes32Set private _sentBox;

    /// @inheritdoc IGateway
    function messageId(Message memory message) public pure virtual returns (bytes32) {
        return keccak256(abi.encode(message));
    }

    /// @inheritdoc IGatewaySource
    function sendingStatus(bytes32 id) public view virtual returns (MessageSourceStatus) {
        if (_sentBox.contains(id)) return MessageSourceStatus.Sent;
        if (_createdBox.contains(id)) return MessageSourceStatus.Created;
        return MessageSourceStatus.Unknown;
    }

    /// @inheritdoc IGatewaySource
    function sendRequest(Message memory message) external payable virtual returns (bytes32) {
        return _sendRequest(messageId(message), message);
    }

    /// @inheritdoc IGatewaySource
    function createRequest(Message memory message) external payable virtual returns (bytes32) {
        bytes32 id = messageId(message);

        // Check if the message was already sent or created.
        if (sendingStatus(id) == MessageSourceStatus.Unknown) revert DuplicatedSourceMessage(id);

        emit MessageCreated(id, message);
        return id;
    }

    /// @inheritdoc IGatewaySource
    function forwardRequest(Message memory message) external payable virtual returns (bytes32) {
        bytes32 id = messageId(message);
        if (!_createdBox.contains(id)) revert UnknownMessage(id);
        return _sendRequest(id, message);
    }

    function _sendRequest(bytes32 id, Message memory message) internal virtual returns (bytes32) {
        // Check if the message was already sent.
        if (_createdBox.insert(id)) revert DuplicatedSourceMessage(id);

        _processSend(id, message);
        emit MessageSent(id, message);
        return id;
    }

    /// @dev Process a cross-chain message sent. Its up to the gateway to implement the logic.
    function _processSend(bytes32 id, Message memory message) internal virtual;
}

abstract contract GatewayDestination is IGatewayDestination {
    using Set for Set.Bytes32Set;
    Set.Bytes32Set private _executedBox;
    Set.Bytes32Set private _deliveredBox;

    /// @inheritdoc IGateway
    function messageId(Message memory message) public pure virtual returns (bytes32) {
        return keccak256(abi.encode(message));
    }

    /// @inheritdoc IGatewayDestination
    function destinationStatus(bytes32 id) public view virtual returns (MessageDestinationStatus) {
        if (_executedBox.contains(id)) return MessageDestinationStatus.Executed;
        if (_deliveredBox.contains(id)) return MessageDestinationStatus.Delivered;
        return MessageDestinationStatus.Unknown;
    }

    /// @inheritdoc IGatewayDestination
    function setRequestDelivered(Message memory message) external virtual returns (bytes32) {
        bytes32 id = messageId(message);

        // Check if the message was already delivered or executed.
        if (destinationStatus(id) == MessageDestinationStatus.Unknown) revert DuplicatedDestinationMessage(id);

        _processDelivery(id, message);
        emit MessageDelivered(id, message);
        return id;
    }

    /// @inheritdoc IGatewayDestination
    function setRequestExecuted(Message memory message) external virtual returns (bytes32) {
        bytes32 id = messageId(message);
        if (!_executedBox.insert(id)) revert DuplicatedDestinationMessage(id);
        emit MessageExecuted(id, message);
        return id;
    }

    /// @dev Process a cross-chain message delivery. Its up to the gateway to implement the logic.
    function _processDelivery(bytes32 id, Message memory message) internal virtual;
}

/// @dev Generic implementation of a Gateway contract according to ERC-XXXX definitions.
abstract contract Gateway is GatewayDestination, GatewaySource {
    function messageId(
        Message memory message
    ) public pure override(GatewayDestination, GatewaySource) returns (bytes32) {
        return super.messageId(message);
    }
}
