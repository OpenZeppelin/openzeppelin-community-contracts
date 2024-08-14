// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IGatewayDestination, IGatewaySource, IGatewayBase} from "./IGateway.sol";
import {Set} from "../utils/Set.sol";
import {CAIP10} from "../utils/CAIP-10.sol";
import {CAIP2} from "../utils/CAIP-2.sol";

/// @dev Gateway contract on the source chain according to ERC-XXXX definitions.
///
/// This is a generic implementation of an asynchronous message-passing system between accounts on different chains.
abstract contract GatewaySource is IGatewaySource {
    using Set for Set.Bytes32Set;
    using CAIP2 for CAIP2.ChainId;
    using CAIP10 for CAIP10.Account;

    Set.Bytes32Set private _createdBox;
    Set.Bytes32Set private _sentBox;

    /// @inheritdoc IGatewayBase
    function messageId(
        string memory source,
        string memory destination,
        Message memory message
    ) public pure virtual returns (bytes32) {
        return keccak256(abi.encode(source, destination, message));
    }

    /// @inheritdoc IGatewaySource
    function sendingStatus(bytes32 id) public view virtual returns (MessageSourceStatus) {
        if (_sentBox.contains(id)) return MessageSourceStatus.Sent;
        if (_createdBox.contains(id)) return MessageSourceStatus.Created;
        return MessageSourceStatus.Unknown;
    }

    /// @inheritdoc IGatewaySource
    function sendMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external payable virtual returns (bytes32) {
        _authorizeSendingMessage(source, source, message);
        bytes32 id = messageId(source, destination, message);
        return _sendMessage(id, sendingStatus(id), message);
    }

    /// @inheritdoc IGatewaySource
    function createMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external payable virtual returns (bytes32) {
        _authorizeSendingMessage(source, message);
        bytes32 id = messageId(source, destination, message);
        return _createMessage(id, sendingStatus(id), message);
    }

    /// @inheritdoc IGatewaySource
    function forwardMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external payable virtual returns (bytes32) {
        bytes32 id = messageId(source, destination, message);
        return _forwardMessage(id, sendingStatus(id), message);
    }

    function _authorizeSendingMessage(string memory source, Message memory message) internal virtual {
        CAIP10.Account memory sourceAccount = CAIP10.fromString(source);

        // Sender must match the source account
        bool isSelf = Strings.equal(Strings.toHexString(msg.sender), sourceAccount._accountId);

        if (!isSelf || !_EVMValidity()) {
            revert UnauthorizedSourceMessage(source, msg.sender, message);
        }
    }

    function _EVMValidity(CAIP10.Account memory sourceAccount) private pure {
        return
            sourceAccount._chainId._namespace == _chainId() && // Chain ID must match the current chain
            sourceAccount._chainId._reference == bytes32(bytes(string("eip155"))); // EIP-155 for EVM chains
    }

    function _createMessage(bytes32 id, MessageSourceStatus status, Message memory message) private returns (bytes32) {
        // Check if the message was not created or sent before. NOOP otherwise.
        if (status == MessageSourceStatus.Unknown) {
            _createdBox.insert(id);
            emit MessageCreated(id, message);
        }
        return id;
    }

    function _sendMessage(bytes32 id, MessageSourceStatus status, Message memory message) private returns (bytes32) {
        /// Check if the message hwas not sent before. NOOP otherwise.
        if (status != MessageSourceStatus.Sent) {
            _sentBox.insert(id);
            emit MessageSent(id, message);
        }
        return id;
    }

    function _forwardMessage(bytes32 id, MessageSourceStatus status, Message memory message) private returns (bytes32) {
        // Check if the message was created first. NOOP otherwise.
        if (status == MessageSourceStatus.Created) {
            _sendMessage(id, status, message);
        }
        return id;
    }

    /// @dev Returns the chain ID of the current chain.
    /// Assumes block.chainId < type(uint64).max
    function _chainId() private view returns (bytes8 chainId) {
        unchecked {
            uint256 id = block.chainid;
            while (true) {
                chainId--;
                assembly ("memory-safe") {
                    mstore8(chainId, byte(mod(id, 10), HEX_DIGITS))
                }
                id /= 10;
                if (id == 0) break;
            }
        }
    }
}

abstract contract GatewayDestination is IGatewayDestination {
    using Set for Set.Bytes32Set;
    Set.Bytes32Set private _executedBox;
    Set.Bytes32Set private _deliveredBox;

    /// @inheritdoc IGatewayBase
    function messageId(
        string memory source,
        string memory destination,
        Message memory message
    ) public pure virtual returns (bytes32) {
        return keccak256(abi.encode(source, destination, message));
    }

    /// @inheritdoc IGatewayDestination
    function destinationStatus(bytes32 id) public view virtual returns (MessageDestinationStatus) {
        if (_executedBox.contains(id)) return MessageDestinationStatus.Executed;
        if (_deliveredBox.contains(id)) return MessageDestinationStatus.Delivered;
        return MessageDestinationStatus.Unknown;
    }

    /// @inheritdoc IGatewayDestination
    function deliverMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external virtual returns (bytes32) {
        bytes32 id = messageId(source, destination, message);
        _authorizeDeliveringMessage(destination, message);
        MessageDestinationStatus status = destinationStatus(id);
        return _deliverMessage(id, status, message);
    }

    /// @inheritdoc IGatewayDestination
    function setMessageExecuted(
        string memory source,
        string memory destination,
        Message memory message
    ) external virtual returns (bytes32) {
        bytes32 id = messageId(source, destination, message);
        MessageDestinationStatus status = destinationStatus(id);
        return _setMessageExecuted(id, status, message);
    }

    /// @dev Authorizes the delivery of a message to the destination chain.
    function _authorizeDeliveringMessage(string memory destination, Message memory message) internal virtual {
        CAIP10.Account memory destinationAccount = CAIP10.fromString(destination);

        if (_validateMessage(message) && !_EVMValidity(destinationAccount)) {
            revert UnauthorizedDestinationMessage(destination, msg.sender, message);
        }
    }

    /// @dev Validates the message before delivering it. Left unimplemented to allow for custom access control.
    function _validateMessage(Message memory message) internal virtual;

    function _deliverMessage(
        bytes32 id,
        MessageDestinationStatus status,
        Message memory message
    ) private returns (bytes32) {
        // Check if the message was not delivered or executed before. NOOP otherwise.
        if (status == MessageDestinationStatus.Unknown) {
            _deliveredBox.insert(id);
            emit MessageDelivered(id, message);
        }
        return id;
    }

    function _EVMValidity(CAIP10.Account memory destinationAccount) private pure {
        return
            destinationAccount._chainId._namespace == _chainId() && // Chain ID must match the current chain
            destinationAccount._chainId._reference == bytes32(bytes(string("eip155"))); // EIP-155 for EVM chains
    }

    function _setMessageExecuted(
        bytes32 id,
        MessageDestinationStatus status,
        Message memory message
    ) private returns (bytes32) {
        // Check if the message was not executed already. NOOP otherwise.
        if (status != MessageDestinationStatus.Executed) {
            _executedBox.insert(id);
            emit MessageExecuted(id, message);
        }
        return id;
    }
}

/// @dev Generic implementation of a Gateway contract according to ERC-XXXX definitions.
abstract contract Gateway is GatewayDestination, GatewaySource {
    function messageId(
        string memory source,
        string memory destination,
        Message memory message
    ) public pure override(GatewaySource, GatewayDestination) returns (bytes32) {
        return super.messageId(source, destination, message);
    }
}
