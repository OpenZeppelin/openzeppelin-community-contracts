// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGatewaySource {
    struct Message {
        string source; // CAIP-10 account ID
        string destination; // CAIP-10 account ID
        bytes payload;
        bytes[] attributes;
    }

    event MessageCreated(bytes32 indexed messageId, Message message);
    event MessageSent(bytes32 indexed messageId);

    function sendMessage(
        string calldata destChain, // CAIP-2 chain ID
        string calldata destAccount, // i.e. address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 messageId);
}
