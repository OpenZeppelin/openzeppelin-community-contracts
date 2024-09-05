// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGatewayDestinationPassive {
    error GatewayDestinationPassiveInvalidMessage(bytes32 messageDestinationId);

    function validateReceivedMessage(
        bytes32 messageDestinationId,
        string calldata srcChain,
        string calldata srcAccount,
        bytes calldata payload,
        bytes calldata attributes
    ) external;
}
