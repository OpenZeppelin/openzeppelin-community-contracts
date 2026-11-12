// contracts/MyStablecoinAllowlist.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {ERC20AllowlistUpgradeable, ERC20Upgradeable} from "../../token/ERC20/extensions/ERC20AllowlistUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract MyStablecoinAllowlistUpgradeable is Initializable, ERC20AllowlistUpgradeable, AccessManagedUpgradeable {
    function __MyStablecoinAllowlist_init(address initialAuthority) internal onlyInitializing {
        __ERC20_init_unchained("MyStablecoin", "MST");
        __AccessManaged_init_unchained(initialAuthority);
    }

    function __MyStablecoinAllowlist_init_unchained(address) internal onlyInitializing {}

    function allowUser(address user) public restricted {
        _allowUser(user);
    }

    function disallowUser(address user) public restricted {
        _disallowUser(user);
    }
}
