// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {CAIP10} from "../utils/CAIP-10.sol";
import {CAIP2} from "../utils/CAIP-2.sol";
import {IGatewayDestination, IGatewayCommon} from "./IGatewayDestination.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Set} from "../utils/Set.sol";

/// @dev A gateway destination that receives messages from a source chain.
///
/// This contract allows for 2 main operations:
/// - Message delivery (i.e. making it available for execution)
/// - Message execution (i.e. marking it as executed)
///
/// Message delivery is permissioned through {_authorizeMessageDelivered} and it's usually set
/// to an authority that can validate the message and make it available for execution.
///
/// Message execution is permissioned through {_authorizeMessageExecuted} and it checks if the
/// destination account is the one marking the message as executed.
abstract contract GatewayDestination is IGatewayDestination {
    /// @inheritdoc IGatewayCommon
    function messageId(
        string memory source,
        string memory destination,
        Message memory message
    ) public pure virtual override returns (bytes32);

    /// @inheritdoc IGatewayDestination
    function destinationStatus(bytes32 id) public view virtual override returns (MessageDestinationStatus);

    /// @inheritdoc IGatewayDestination
    function deliverMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external returns (bytes32) {
        bytes32 id = messageId(source, destination, message);
        MessageDestinationStatus status = destinationStatus(id);
        _validateCurrentChain(destination);
        _authorizeMessageDelivered(destination, message);
        return _deliverMessage(id, status, message);
    }

    /// @inheritdoc IGatewayDestination
    function setMessageExecuted(
        string memory source,
        string memory destination,
        Message memory message
    ) external returns (bytes32) {
        bytes32 id = messageId(source, destination, message);
        MessageDestinationStatus status = destinationStatus(id);
        _authorizeMessageExecuted(destination, message);
        return _setMessageExecuted(id, status, message);
    }

    /// @dev Internal version of {deliverMessage} without access control.
    function _deliverMessage(
        bytes32 id,
        MessageDestinationStatus status,
        Message memory message
    ) internal virtual returns (bytes32) {
        // Check if the message was not delivered or executed before. NOOP otherwise.
        if (status == MessageDestinationStatus.Unknown) {
            emit MessageDelivered(id, message);
        }
        return id;
    }

    /// @dev Internal version of {setMessageExecuted} without access control.
    function _setMessageExecuted(
        bytes32 id,
        MessageDestinationStatus status,
        Message memory message
    ) internal virtual returns (bytes32) {
        // Check if the message was not executed already. NOOP otherwise.
        if (status != MessageDestinationStatus.Executed) {
            emit MessageExecuted(id, message);
        }
        return id;
    }

    /// @dev Authorizes the delivery of a message to the destination chain.
    function _authorizeMessageDelivered(string memory destination, Message memory message) internal virtual;

    /// @dev Validates a message submitted as executed.
    ///
    /// Requirements:
    /// - The destination must be the `msg.sender`
    function _authorizeMessageExecuted(string memory destination, Message memory message) internal virtual {
        CAIP10.Account memory destinationAccount = CAIP10.fromString(destination);

        if (CAIP10.getAddress(destinationAccount) != msg.sender) {
            revert UnauthorizedDestinationMessage(destination, msg.sender, message);
        }
    }

    /// @dev Validates that the destination chain is the current chain.
    function _validateCurrentChain(string memory destination) private view {
        CAIP10.Account memory destinationAccount = CAIP10.fromString(destination);
        if (!CAIP2.isCurrentEVMChain(destinationAccount._chainId)) {
            revert MismatchedDestinationChain(destination);
        }
    }
}
