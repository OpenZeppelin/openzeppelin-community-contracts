// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

// This is just so that ERC4626 is imported and exposed from @openzeppelin/contracts
// We use it to validate compatibility of the ERC4626.behavior tests with our reference implementation.
abstract contract ERC4626Mock is ERC4626 {}
