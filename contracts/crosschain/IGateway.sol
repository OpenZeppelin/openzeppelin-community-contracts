// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @dev Interface for a generic cross-chain gateway.
/// The gateway is responsible for sending and receiving messages between different blockchains.
interface IGateway {
    /// @dev Represents an account on a specific chain. Might be a contract.
    struct Account {
        uint256 chain;
        address instance;
    }

    /// @dev Represents a cross-chain message.
    struct Message {
        Account source;
        Account destination;
        // Native token value to be sent with the message.
        uint256 value;
        // Arbitrary data to be sent with the message.
        bytes payload;
        // Extra parameters to be used by the gateway specialization.
        bytes extraParams;
    }

    /// @dev Uniquely identifies a message.
    function messageId(Message memory message) external pure returns (bytes32);
}

/// @dev Interface for a cross-chain gateway that sends messages.
/// Allows for 2 sending modes: {sendRequest} and {createRequest} + {forwardRequest},
/// where the latter allows to hook logic before sending the message.
interface IGatewaySource is IGateway {
    enum MessageSourceStatus {
        Unknown,
        Created,
        Sent
    }

    event MessageCreated(bytes32 indexed id, Message message);
    event MessageSent(bytes32 indexed id, Message message);

    /// @dev Emitted when a message is created with the same id as a previous one (either created or sent).
    error DuplicatedSourceMessage(bytes32 id);

    /// @dev Emitted when trying to forward a message that was not created.
    error UnknownMessage(bytes32 id);

    /// @dev Returns the status of a sent cross-chain request.
    function sendingStatus(bytes32 id) external view returns (MessageSourceStatus);

    /// @dev Send a cross-chain message to the target chain.
    /// MessageSourceStatus.Unknown -> MessageSourceStatus.Sent
    function sendRequest(Message memory message) external payable returns (bytes32);

    /// @dev Create a cross-chain message to the target chain. See {forwardRequest} to send it.
    /// MessageSourceStatus.Unknown -> MessageSourceStatus.Created
    function createRequest(Message memory message) external payable returns (bytes32);

    /// @dev Forwards a previously created cross-chain message to the target chain. See {createRequest} to create it.
    /// MessageSourceStatus.Created -> MessageSourceStatus.Sent
    function forwardRequest(Message memory message) external payable returns (bytes32);
}

/// @dev Interface for a cross-chain gateway that receives messages.
/// Allows to check the status of a message and to mark it as delivered or executed.
interface IGatewayDestination is IGateway {
    enum MessageDestinationStatus {
        Unknown,
        Delivered,
        Executed
    }

    event MessageDelivered(bytes32 indexed id, Message message);
    event MessageExecuted(bytes32 indexed id, Message message);

    /// @dev Emitted when a message is delivered with the same id as a previous one (either delivered or executed).
    error DuplicatedDestinationMessage(bytes32 id);

    /// @dev Returns the status of a received cross-chain request.
    function destinationStatus(bytes32 id) external view returns (MessageDestinationStatus);

    /// @dev Sets a cross-chain request as delivered, ready for execution.
    /// MessageDestinationStatus.Unknown -> MessageDestinationStatus.Delivered
    /// NOTE: Should only be called by an authorized gateway operator.
    function setRequestDelivered(Message memory message) external returns (bytes32);

    /// @dev Marks a cross-chain request as executed.
    /// MessageDestinationStatus.Unknown -> MessageDestinationStatus.Executed
    /// MessageDestinationStatus.Delivered -> MessageDestinationStatus.Executed
    /// NOTE: Should only be called by the destination account.
    function setRequestExecuted(Message memory message) external returns (bytes32);
}
