// contracts/MyFactoryAccount.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {AccountFactory} from "../../../account/AccountFactory.sol";

contract MyFactoryAccount is AccountFactory {
    constructor(address impl_) AccountFactory(impl_) {}
}
