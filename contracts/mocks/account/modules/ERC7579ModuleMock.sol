// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC7579Module} from "../../../account/modules/ERC7579Module.sol";

contract ERC7579ModuleMock is ERC7579Module {
    constructor(uint256 moduleTypeId) ERC7579Module(moduleTypeId) {}
}
