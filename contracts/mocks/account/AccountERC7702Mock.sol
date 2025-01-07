// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../account/Account.sol";
import {AccountSignerERC7702} from "../../account/extensions/AccountSignerERC7702.sol";

abstract contract AccountERC7702Mock is Account, AccountSignerERC7702 {}
