// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {MODULE_TYPE_VALIDATOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {AccountERC7579Hooked} from "../../account/extensions/AccountERC7579Hooked.sol";

abstract contract AccountERC7579HookedMock is AccountERC7579Hooked {
    constructor(address validator, bytes memory initData) {
        _installModule(MODULE_TYPE_VALIDATOR, validator, initData);
    }
}
