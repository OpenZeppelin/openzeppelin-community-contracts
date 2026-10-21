// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

contract DispatchModuleMock {
    event Call(address sender, uint256 value, bytes data);

    fallback() external payable {
        emit Call(msg.sender, msg.value, msg.data);
    }
}
