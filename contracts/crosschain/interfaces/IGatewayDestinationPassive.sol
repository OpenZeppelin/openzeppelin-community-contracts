// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGatewayDestinationPassive {
    error InvalidMessageKey(bytes messageKey);

    function validateReceivedMessage(
        bytes calldata messageKey,
        string calldata source,
        string calldata sender,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external;
}
