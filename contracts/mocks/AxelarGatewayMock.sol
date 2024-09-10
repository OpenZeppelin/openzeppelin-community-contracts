// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

contract AxelarGatewayMock {
    event CallContract(string destinationChain, string contractAddress, bytes payload);

    function callContract(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload
    ) external {
        emit CallContract(destinationChain, contractAddress, payload);
    }
}
