// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20Upgradeable, ERC20CustodianUpgradeable} from "../../token/ERC20/extensions/ERC20CustodianUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract ERC20CustodianMockUpgradeable is Initializable, ERC20CustodianUpgradeable {
    address private _custodian;

    function __ERC20CustodianMock_init(address custodian, string memory name_, string memory symbol_) internal onlyInitializing {
        __ERC20_init_unchained(name_, symbol_);
        __ERC20CustodianMock_init_unchained(custodian, name_, symbol_);
    }

    function __ERC20CustodianMock_init_unchained(address custodian, string memory, string memory) internal onlyInitializing {
        _custodian = custodian;
    }

    function _isCustodian(address user) internal view override returns (bool) {
        return user == _custodian;
    }
}
