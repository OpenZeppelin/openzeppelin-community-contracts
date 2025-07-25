// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

contract AxelarGasServiceMock {
    event NativeGasPaidForContractCall(
        address indexed sourceAddress,
        string destinationChain,
        string destinationAddress,
        bytes32 indexed payloadHash,
        uint256 gasFeeAmount,
        address refundAddress
    );

    function payNativeGasForContractCall(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address refundAddress
    ) external payable {
        emit NativeGasPaidForContractCall(
            sender,
            destinationChain,
            destinationAddress,
            keccak256(payload),
            msg.value,
            refundAddress
        );
    }
}
