// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IGatewayCommon} from "./IGatewayCommon.sol";

/// @dev Interface for a cross-chain gateway that receives messages.
///
/// Allows to check the status of a message and to mark it as delivered or executed.
interface IGatewayDestination is IGatewayCommon {
    enum MessageDestinationStatus {
        Unknown,
        Delivered,
        Executed
    }

    event MessageDelivered(bytes32 indexed id, Message message);
    event MessageExecuted(bytes32 indexed id, Message message);

    error UnauthorizedDestinationMessage(string destination, address sender, Message message);
    error MismatchedDestinationChain(string destination);

    /// @dev Returns the status of a received cross-chain message.
    function destinationStatus(bytes32 id) external view returns (MessageDestinationStatus);

    /// @dev Sets a cross-chain message as delivered, ready for execution.
    /// MessageDestinationStatus.Unknown -> MessageDestinationStatus.Delivered
    /// NOTE: Should only be called by an authorized gateway operator and validate that destination is the current chain.
    function deliverMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external returns (bytes32);

    /// @dev Sets a cross-chain message as executed.
    /// MessageDestinationStatus.Unknown -> MessageDestinationStatus.Executed.
    /// MessageDestinationStatus.Delivered -> MessageDestinationStatus.Executed.
    /// NOTE: Should only be called by the destination account.
    function setMessageExecuted(
        string memory source,
        string memory destination,
        Message memory message
    ) external returns (bytes32);
}
