// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CAIP10} from "../utils/CAIP-10.sol";
import {CAIP2} from "../utils/CAIP-2.sol";
import {IGatewaySource, IGatewayCommon} from "./IGatewaySource.sol";
import {Set} from "../utils/Set.sol";

/// @dev Gateway contract on the source chain according to ERC-XXXX definitions.
///
/// This is a generic implementation of an asynchronous message-passing system between accounts on different chains.
abstract contract GatewaySource is IGatewaySource {
    /// @inheritdoc IGatewayCommon
    function messageId(
        string memory source,
        string memory destination,
        Message memory message
    ) public pure virtual returns (bytes32);

    /// @inheritdoc IGatewaySource
    function sendingStatus(bytes32 id) public view virtual returns (MessageSourceStatus);

    /// @inheritdoc IGatewaySource
    function sendMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external payable virtual returns (bytes32) {
        bytes32 id = messageId(source, destination, message);
        _validateCurrentChain(source);
        _authorizeMessageCreated(source, message);
        return _sendMessage(id, sendingStatus(id), message);
    }

    /// @inheritdoc IGatewaySource
    function createMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external payable virtual returns (bytes32) {
        bytes32 id = messageId(source, destination, message);
        _validateCurrentChain(source);
        _authorizeMessageCreated(source, message);
        return _createMessage(id, sendingStatus(id), message);
    }

    /// @inheritdoc IGatewaySource
    function forwardMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external payable virtual returns (bytes32) {
        bytes32 id = messageId(source, destination, message);
        _authorizeMessageForwarded(destination, message);
        return _forwardMessage(id, sendingStatus(id), message);
    }

    /// @dev Internal version of {createMessage} without access control.
    function _createMessage(
        bytes32 id,
        MessageSourceStatus status,
        Message memory message
    ) internal virtual returns (bytes32) {
        // Check if the message was not created or sent before. NOOP otherwise.
        if (status == MessageSourceStatus.Unknown) {
            emit MessageCreated(id, message);
        }
        return id;
    }

    /// @dev Internal version of {sendMessage} without access control.
    function _sendMessage(
        bytes32 id,
        MessageSourceStatus status,
        Message memory message
    ) internal virtual returns (bytes32) {
        /// Check if the message hwas not sent before. NOOP otherwise.
        if (status != MessageSourceStatus.Sent) {
            emit MessageSent(id, message);
        }
        return id;
    }

    /// @dev Internal version of {forwardMessage} without access control.
    function _forwardMessage(
        bytes32 id,
        MessageSourceStatus status,
        Message memory message
    ) internal virtual returns (bytes32) {
        // Check if the message was created first. NOOP otherwise.
        if (status == MessageSourceStatus.Created) {
            _sendMessage(id, status, message);
        }
        return id;
    }

    /// @dev Authorizes the creation of a message on the source chain.
    ///
    /// Requirements:
    /// - The source chain must match `msg.sender`
    function _authorizeMessageCreated(string memory source, Message memory message) internal virtual {
        CAIP10.Account memory sourceAccount = CAIP10.fromString(source);

        if (CAIP10.getAddress(sourceAccount) != msg.sender) {
            revert UnauthorizedSourceMessage(source, msg.sender, message);
        }
    }

    /// @dev Authorizes the forwarding of a message to the destination chain.
    function _authorizeMessageForwarded(string memory destination, Message memory message) internal virtual;

    /// @dev Validates that the source chain is the current chain.
    function _validateCurrentChain(string memory source) private view {
        CAIP10.Account memory sourceAccount = CAIP10.fromString(source);
        if (!CAIP2.isCurrentEVMChain(sourceAccount._chainId)) {
            revert MismatchedSourceChain(source);
        }
    }
}

abstract contract GatewaySourceGeneric is GatewaySource {
    using Set for Set.Bytes32Set;
    using CAIP10 for CAIP10.Account;

    Set.Bytes32Set private _createdBox;
    Set.Bytes32Set private _sentBox;

    /// @inheritdoc IGatewayCommon
    function messageId(
        string memory source,
        string memory destination,
        Message memory message
    ) public pure override returns (bytes32) {
        return keccak256(abi.encode(source, destination, message));
    }

    /// @inheritdoc IGatewaySource
    function sendingStatus(bytes32 id) public view virtual override returns (MessageSourceStatus) {
        if (_sentBox.contains(id)) return MessageSourceStatus.Sent;
        if (_createdBox.contains(id)) return MessageSourceStatus.Created;
        return MessageSourceStatus.Unknown;
    }
}
