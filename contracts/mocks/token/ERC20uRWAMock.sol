// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20uRWA} from "../../token/ERC20/extensions/ERC20uRWA.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

abstract contract ERC20uRWAMock is ERC20uRWA, AccessControl {
    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER_ROLE");
    bytes32 public constant ENFORCER_ROLE = keccak256("ENFORCER_ROLE");

    constructor(address freezer, address enforcer) {
        _grantRole(FREEZER_ROLE, freezer);
        _grantRole(ENFORCER_ROLE, enforcer);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC20uRWA, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _checkEnforcer(address, address, uint256) internal view override onlyRole(ENFORCER_ROLE) {}

    function _checkFreezer(address, uint256) internal view override onlyRole(FREEZER_ROLE) {}
}
