// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGatewaySource {
    event MessageCreated(
        bytes32 messageId,
        string source, // CAIP-10 account ID
        string destination, // CAIP-10 account ID
        bytes payload,
        bytes[] attributes
    );

    event MessageSent(bytes32 indexed messageId);

    function sendMessage(
        string calldata destChain, // CAIP-2 chain ID
        string calldata destAccount, // CAIP-10 account ID
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 messageId);
}
