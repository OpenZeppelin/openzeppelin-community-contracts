// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IAuthority} from "@openzeppelin/contracts/access/manager/IAuthority.sol";
import {Masks} from "../../utils/Masks.sol";

contract AccessManagerLight is IAuthority {
    using Masks for *;

    uint8 public constant ADMIN = 0x00;
    uint8 public constant PUBLIC = 0xFF;
    Masks.Mask public immutable ADMIN_MASK = ADMIN.toMask();
    Masks.Mask public immutable PUBLIC_MASK = PUBLIC.toMask();

    mapping(address => Masks.Mask) private _permissions;
    mapping(address => mapping(bytes4 => Masks.Mask)) private _restrictions;
    mapping(uint8 => Masks.Mask) private _admin;

    event GroupAdded(address indexed user, uint8 indexed group);
    event GroupRemoved(address indexed user, uint8 indexed group);
    event GroupAdmins(uint8 indexed group, Masks.Mask admins);
    event Requirements(address indexed target, bytes4 indexed selector, Masks.Mask groups);

    error MissingPermissions(address user, Masks.Mask permissions, Masks.Mask restriction);

    modifier onlyRole(Masks.Mask restriction) {
        Masks.Mask permissions = getGroups(msg.sender);
        if (permissions.intersection(restriction).isEmpty()) {
            revert MissingPermissions(msg.sender, permissions, restriction);
        }
        _;
    }

    constructor(address admin) {
        _addGroup(admin, 0);
    }

    // Getters
    function canCall(address caller, address target, bytes4 selector) public view returns (bool) {
        return !getGroups(caller).intersection(getRequirements(target, selector)).isEmpty();
    }

    function getGroups(address user) public view returns (Masks.Mask) {
        return _permissions[user].union(PUBLIC_MASK);
    }

    function getGroupAdmins(uint8 group) public view returns (Masks.Mask) {
        return _admin[group].union(ADMIN_MASK); // Admin have power over all groups
    }

    function getRequirements(address target, bytes4 selector) public view returns (Masks.Mask) {
        return _restrictions[target][selector].union(ADMIN_MASK); // Admins can call an function
    }

    // Group management
    function addGroup(address user, uint8 group) public onlyRole(getGroupAdmins(group)) {
        _addGroup(user, group);
    }

    function remGroup(address user, uint8 group) public onlyRole(getGroupAdmins(group)) {
        _remGroup(user, group);
    }

    function _addGroup(address user, uint8 group) internal {
        _permissions[user] = _permissions[user].union(group.toMask());
        emit GroupAdded(user, group);
    }

    function _remGroup(address user, uint8 group) internal {
        _permissions[user] = _permissions[user].difference(group.toMask());
        emit GroupRemoved(user, group);
    }

    // Group admin management
    function setGroupAdmins(uint8 group, uint8[] calldata admins) public onlyRole(ADMIN_MASK) {
        _setGroupAdmins(group, admins.toMask());
    }

    function _setGroupAdmins(uint8 group, Masks.Mask admins) internal {
        _admin[group] = admins;
        emit GroupAdmins(group, admins);
    }

    // Requirement management
    function setRequirements(
        address target,
        bytes4[] calldata selectors,
        uint8[] calldata groups
    ) public onlyRole(ADMIN_MASK) {
        Masks.Mask mask = groups.toMask();
        for (uint256 i = 0; i < selectors.length; ++i) {
            _setRequirements(target, selectors[i], mask);
        }
    }

    function _setRequirements(address target, bytes4 selector, Masks.Mask groups) internal {
        _restrictions[target][selector] = groups;
        emit Requirements(target, selector, groups);
    }
}
