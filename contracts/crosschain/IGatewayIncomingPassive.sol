// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGatewayIncoming {
    event MessageExecuted(bytes32 indexed id);
}

interface IGatewayIncomingPassive {
    function validateReceivedMessage(
        bytes32 messageId,
        string calldata srcChain,
        string calldata srcAccount,
        bytes calldata payload,
        bytes calldata attributes
    ) external;
}
