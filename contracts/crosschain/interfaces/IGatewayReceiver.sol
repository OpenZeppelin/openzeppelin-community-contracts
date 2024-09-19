// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IGatewayReceiver {
    function receiveMessage(
        address gateway,
        bytes calldata gatewayMessageKey,
        string calldata source,
        string calldata sender,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable;
}
