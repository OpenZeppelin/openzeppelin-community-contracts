// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @dev Interface for a generic cross-chain gateway.
/// The gateway is responsible for sending and receiving messages between different blockchains.
interface IGatewayBase {
    /// @dev Represents a cross-chain message.
    struct Message {
        // Native token value to be sent with the message.
        uint256 value;
        // Arbitrary data to be sent with the message.
        bytes payload;
        // Extra parameters to be used by the gateway specialization.
        bytes extraParams;
    }

    /// @dev Uniquely identifies a message.
    /// @param source CAIP-10 account ID of the source chain.
    /// @param destination CAIP-10 account ID of the destination chain.
    function messageId(
        string memory source,
        string memory destination,
        Message memory message
    ) external pure returns (bytes32);
}

/// @dev Interface for a cross-chain gateway that sends messages.
/// Allows for 2 sending modes: {sendMessage} and {createMessage} + {forwardMessage},
/// where the latter allows to hook logic before sending the message.
interface IGatewaySource is IGatewayBase {
    enum MessageSourceStatus {
        Unknown,
        Created,
        Sent
    }

    event MessageCreated(bytes32 indexed id, Message message);
    event MessageSent(bytes32 indexed id, Message message);

    error UnauthorizedSourceMessage(string source, address sender, Message message);

    /// @dev Returns the status of a sent cross-chain message.
    function sendingStatus(bytes32 id) external view returns (MessageSourceStatus);

    /// @dev Send a cross-chain message to the target chain.
    /// MessageSourceStatus.Unknown -> MessageSourceStatus.Sent
    function sendMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external payable returns (bytes32);

    /// @dev Create a cross-chain message to the target chain. See {forwardMessage} to send it.
    /// MessageSourceStatus.Unknown -> MessageSourceStatus.Created
    function createMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external payable returns (bytes32);

    /// @dev Forwards a previously created cross-chain message to the target chain. See {createMessage} to create it.
    /// MessageSourceStatus.Created -> MessageSourceStatus.Sent
    function forwardMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external payable returns (bytes32);
}

/// @dev Interface for a cross-chain gateway that receives messages.
/// Allows to check the status of a message and to mark it as delivered or executed.
interface IGatewayDestination is IGatewayBase {
    enum MessageDestinationStatus {
        Unknown,
        Delivered,
        Executed
    }

    event MessageDelivered(bytes32 indexed id, Message message);
    event MessageExecuted(bytes32 indexed id, Message message);

    /// @dev Returns the status of a received cross-chain message.
    function destinationStatus(bytes32 id) external view returns (MessageDestinationStatus);

    /// @dev Sets a cross-chain message as delivered, ready for execution.
    /// MessageDestinationStatus.Unknown -> MessageDestinationStatus.Delivered
    /// NOTE: Should only be called by an authorized gateway operator.
    function deliverMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external returns (bytes32);

    /// @dev Marks a cross-chain message as executed.
    /// MessageDestinationStatus.Unknown -> MessageDestinationStatus.Executed.
    /// MessageDestinationStatus.Delivered -> MessageDestinationStatus.Executed.
    /// NOTE: Should only be called by the destination account.
    function setMessageExecuted(
        string memory source,
        string memory destination,
        Message memory message
    ) external returns (bytes32);
}
