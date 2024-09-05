// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGatewayDestination {
    event MessageExecuted(bytes32 indexed messageId);
}
