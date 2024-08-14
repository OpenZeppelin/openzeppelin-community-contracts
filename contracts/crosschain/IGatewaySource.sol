// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IGatewayCommon} from "./IGatewayCommon.sol";

/// @dev Interface for a cross-chain gateway that sends messages.
///
/// Allows for 2 sending modes: {sendMessage} and {createMessage} + {forwardMessage},
/// where the latter allows to hook logic before sending the message.
interface IGatewaySource is IGatewayCommon {
    enum MessageSourceStatus {
        Unknown,
        Created,
        Sent
    }

    event MessageCreated(bytes32 indexed id, Message message);
    event MessageSent(bytes32 indexed id, Message message);

    error UnauthorizedSourceMessage(string source, address sender, Message message);
    error MismatchedSourceChain(string source);

    /// @dev Returns the status of a sent cross-chain message.
    function sendingStatus(bytes32 id) external view returns (MessageSourceStatus);

    /// @dev Send a cross-chain message to the target chain.
    /// MessageSourceStatus.Unknown -> MessageSourceStatus.Sent
    /// NOTE: Must validate that source is the current chain.
    function sendMessage(
        string memory source,
        string memory destination,
        Message memory message
    ) external payable returns (bytes32);

    /// @dev Create a cross-chain message to the target chain. See {forwardMessage} to send it.
    /// MessageSourceStatus.Unknown -> MessageSourceStatus.Created
    /// NOTE: Must validate that source is the current chain.
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
