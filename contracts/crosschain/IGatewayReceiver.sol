// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGatewayReceiver {
    function receiveMessage(
        address gatewayAddr,
        bytes calldata gatewayData,
        string calldata srcChain,
        string calldata srcAccount,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable;
}
