// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../account/Account.sol";
import {ERC7821} from "../../account/extensions/ERC7821.sol";
import {SignerERC7702} from "../../utils/cryptography/SignerERC7702.sol";

abstract contract AccountERC7702Mock is Account, SignerERC7702, ERC7821 {}
