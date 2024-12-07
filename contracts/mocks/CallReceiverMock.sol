// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {CallReceiverMock} from "@openzeppelin/contracts/mocks/CallReceiverMock.sol";

contract CallReceiverMockExtended is CallReceiverMock {
    event MockFunctionCalledExtra(address caller, uint256 value);

    function mockFunctionExtra() public payable {
        emit MockFunctionCalledExtra(msg.sender, msg.value);
    }
}
