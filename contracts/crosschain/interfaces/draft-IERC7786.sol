// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface for ERC-7786 source gateways.
 *
 * See ERC-7786 for more details
 */
interface IERC7786GatewaySource {
    /**
     * @dev Event emitted when a message is created. If `outboxId` is zero, no further processing is necessary. If
     * `outboxId` is not zero, then further (gateway specific, and non-standardized) action is required.
     */
    event MessagePosted(
        bytes32 indexed outboxId,
        string sender, // CAIP-10 account identifier (chain identifier + ":" + account address)
        string receiver, // CAIP-10 account identifier (chain identifier + ":" + account address)
        bytes payload,
        bytes[] attributes
    );

    /// @dev This error is thrown when a message creation fails because of an unsupported attribute being specified.
    error UnsupportedAttribute(bytes4 selector);

    /// @dev Getter to check whether an attribute is supported or not.
    function supportsAttribute(bytes4 selector) external view returns (bool);

    /**
     * @dev Endpoint for creating a new message. If the message requires further (gateway specific) processing before
     * it can be sent to the destination chain, then a non-zero `outboxId` must be returned. Otherwise, the
     * message MUST be sent and this function must return 0.
     *
     * * MUST emit a {MessageCreated} event.
     *
     * If any of the `attributes` is not supported, this function SHOULD revert with an {UnsupportedAttribute} error.
     * Other errors SHOULD revert with errors not specified in ERC-7786.
     */
    function sendMessage(
        string calldata destinationChain, // CAIP-2 chain identifier
        string calldata receiver, // CAIP-10 account address (does not include the chain identifier)
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 outboxId);
}

/**
 * @dev Interface for ERC-7786 destination gateways operating in passive mode.
 *
 * See ERC-7786 for more details
 */
interface IERC7786GatewayDestinationPassive {
    error InvalidMessageKey(bytes messageKey);

    /**
     * @dev Endpoint for checking the validity of a message that is being relayed in passive mode. The message
     * receiver is implicitly the caller of this method, which guarantees that no one but the receiver can
     * "consume" the message. This function MUST implement replay protection, meaning that if called multiple time
     * for same message, all but the first calls MUST revert.
     *
     * NOTE: implementing this interface is OPTIONAL. Some destination gateway MAY only support active mode.
     */
    function setMessageExecuted(
        bytes calldata messageKey,
        string calldata sourceChain, // CAIP-2 chain identifier
        string calldata sender, // CAIP-10 account address (does not include the chain identifier)
        bytes calldata payload,
        bytes[] calldata attributes
    ) external;
}

/**
 * @dev Interface for the ERC-7786 client contract (receiver).
 *
 * See ERC-7786 for more details
 */
interface IERC7786Receiver {
    /**
     * @dev Endpoint for receiving cross-chain message.
     *
     * This function may be called directly by the gateway (active mode) or by a third party (passive mode).
     */
    function executeMessage(
        address gateway,
        bytes calldata gatewayMessageKey,
        string calldata sourceChain, // CAIP-2 chain identifier
        string calldata sender, // CAIP-10 account address (does not include the chain identifier)
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes4);
}