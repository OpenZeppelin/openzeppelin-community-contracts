// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGatewayOutgoing {
    struct Message {
        string source; // CAIP-10 account ID
        string destination; // CAIP-10 account ID
        bytes data;
        bytes attributes;
    }

    event MessageCreated(bytes32 indexed id, Message message);
    event MessageSent(bytes32 indexed id);

    function sendMessage(
        string calldata destChain, // CAIP-2 chain ID
        string calldata destAccount, // i.e. address
        bytes calldata data,
        bytes calldata attributes
    ) external payable returns (bytes32 messageId);
}
