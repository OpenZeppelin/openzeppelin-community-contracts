// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {
    TimelockControllerEnumerable
} from "@openzeppelin/community-contracts/governance/TimelockControllerEnumerable.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract TimelockControllerEnumerableMock is TimelockControllerEnumerable {
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
