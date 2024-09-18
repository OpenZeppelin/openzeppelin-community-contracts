// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGatewayDestinationPassive {
    error GatewayDestinationPassiveInvalidMessage(bytes gatewayData);

    function validateReceivedMessage(
        bytes calldata gatewayData,
        string calldata srcChain,
        string calldata srcAccount,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external;
}
