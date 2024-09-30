// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGatewaySource {
    event MessageCreated(
        bytes32 outboxId,
        string sender, // CAIP-10 account ID
        string receiver, // CAIP-10 account ID
        bytes payload,
        bytes[] attributes
    );

    event MessageSent(bytes32 indexed outboxId);

    error UnsuportedAttribute(bytes4 signature);

    function supportsAttribute(bytes4 signature) external view returns (bool);

    function sendMessage(
        string calldata destination, // CAIP-2 chain ID
        string calldata receiver, // CAIP-10 account ID
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 outboxId);
}
