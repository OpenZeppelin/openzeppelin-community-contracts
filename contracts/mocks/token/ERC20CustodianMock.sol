// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20, ERC20Custodian} from "../../token/ERC20/extensions/ERC20Custodian.sol";

abstract contract ERC20CustodianMock is ERC20Custodian {
    address private immutable _custodian;

    constructor(address custodian, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _custodian = custodian;
    }

    function _isCustodian(address user) internal view override returns (bool) {
        return user == _custodian;
    }
}
