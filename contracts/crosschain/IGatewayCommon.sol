// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @dev Common for a generic cross-chain gateway.
///
/// Gateways are split in two parts: source and destination. Respectively, they are responsible for
/// sending and receiving messages between different blockchains.
interface IGatewayCommon {
    /// @dev Represents a cross-chain message.
    struct Message {
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
