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
     * @param destinationChain {CAIP2} chain identifier
     * @param receiver {CAIP10} account address (does not include the chain identifier)
     *
     * * MUST emit a {MessagePosted} event.
     *
     * If any of the `attributes` is not supported, this function SHOULD revert with an {UnsupportedAttribute} error.
     * Other errors SHOULD revert with errors not specified in ERC-7786.
     */
    function sendMessage(
        string calldata destinationChain,
        string calldata receiver,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 outboxId);
}

/**
 * @dev Interface for the ERC-7786 client contract (receiver).
 *
 * See ERC-7786 for more details
 */
interface IERC7786Receiver {
    /**
     * @dev Endpoint for receiving cross-chain message.
     * @param sourceChain {CAIP2} chain identifier
     * @param sender {CAIP10} account address (does not include the chain identifier)
     *
     * This function may be called directly by the gateway.
     */
    function executeMessage(
        string calldata sourceChain, // CAIP-2 chain identifier
        string calldata sender, // CAIP-10 account address (does not include the chain identifier)
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes4);
}
