// contracts/MyStablecoinAllowlist.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {ERC20Allowlist, ERC20} from "../../token/ERC20/extensions/ERC20Allowlist.sol";

contract MyStablecoinAllowlist is ERC20Allowlist, AccessManaged {
    constructor(address initialAuthority) ERC20("MyStablecoin", "MST") AccessManaged(initialAuthority) {}

    function allowUser(address user) public restricted {
        _allowUser(user);
    }

    function disallowUser(address user) public restricted {
        _disallowUser(user);
    }
}
