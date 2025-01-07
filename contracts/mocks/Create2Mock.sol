// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract Create2Mock {
    function $deploy(uint256 amount, bytes32 salt, bytes memory bytecode) external returns (address) {
        return Create2.deploy(amount, salt, bytecode);
    }

    function $computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address) {
        return Create2.computeAddress(salt, bytecodeHash, address(this));
    }

    function $computeAddress(bytes32 salt, bytes32 bytecodeHash, address deployer) external pure returns (address) {
        return Create2.computeAddress(salt, bytecodeHash, deployer);
    }
}
