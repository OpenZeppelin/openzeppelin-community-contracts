// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IAuthority} from "@openzeppelin/contracts/access/manager/IAuthority.sol";
import {Masks} from "@openzeppelin/community-contracts/utils/Masks.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @dev Light version of an AccessManager contract that defines `bytes8` roles
 * that are stored as requirements (see {getRequirements}) for each function.
 *
 * Each requirement is a bitmask of roles that are allowed to call a function
 * identified by its `bytes4` selector. Users have their permissioned stored
 * as a bitmask of roles they belong to.
 *
 * The admin role is a special role that has access to all functions and can
 * manage the roles of other users.
 */
contract AccessManagerLightUpgradeable is Initializable, IAuthority {
    using Masks for *;

    uint8 public constant ADMIN_ROLE = 0x00;
    uint8 public constant PUBLIC_ROLE = 0xFF;
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    Masks.Mask public immutable ADMIN_MASK = ADMIN_ROLE.toMask();
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    Masks.Mask public immutable PUBLIC_MASK = PUBLIC_ROLE.toMask();

    /// @custom:storage-location erc7201:openzeppelin.storage.AccessManagerLight
    struct AccessManagerLightStorage {
        mapping(address => Masks.Mask) _groups;
        mapping(address => mapping(bytes4 => Masks.Mask)) _requirements;
        mapping(uint8 => Masks.Mask) _admin;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.AccessManagerLight")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AccessManagerLightStorageLocation = 0x6461fda45cba4bb3b5feffe9303f37a85daaff7049bf0239788908394d3c0900;

    function _getAccessManagerLightStorage() private pure returns (AccessManagerLightStorage storage $) {
        assembly {
            $.slot := AccessManagerLightStorageLocation
        }
    }

    event GroupAdded(address indexed user, uint8 indexed group);
    event GroupRemoved(address indexed user, uint8 indexed group);
    event GroupAdmins(uint8 indexed group, Masks.Mask admins);
    event RequirementsSet(address indexed target, bytes4 indexed selector, Masks.Mask groups);

    error MissingPermissions(address user, Masks.Mask permissions, Masks.Mask requirement);

    /// @dev Throws if the specified requirement is not met by the caller's permissions (see {getGroups}).
    modifier onlyRole(Masks.Mask requirement) {
        Masks.Mask permissions = getGroups(msg.sender);
        if (permissions.intersection(requirement).isEmpty()) {
            revert MissingPermissions(msg.sender, permissions, requirement);
        }
        _;
    }

    function initialize(address admin) public virtual initializer {
        __AccessManagerLight_init(admin);
    }
    /// @dev Initializes the contract with the `admin` as the first member of the admin group.
    function __AccessManagerLight_init(address admin) internal onlyInitializing {
        __AccessManagerLight_init_unchained(admin);
    }

    function __AccessManagerLight_init_unchained(address admin) internal onlyInitializing {
        _addGroup(admin, 0);
    }

    /// @dev Returns whether the `caller` has the required permissions to call the `target` with the `selector`.
    function canCall(address caller, address target, bytes4 selector) public view returns (bool) {
        return !getGroups(caller).intersection(getRequirements(target, selector)).isEmpty();
    }

    /// @dev Returns the groups that the `user` belongs to.
    function getGroups(address user) public view returns (Masks.Mask) {
        AccessManagerLightStorage storage $ = _getAccessManagerLightStorage();
        return $._groups[user].union(PUBLIC_MASK);
    }

    /// @dev Returns the admins of the `group`.
    function getGroupAdmins(uint8 group) public view returns (Masks.Mask) {
        AccessManagerLightStorage storage $ = _getAccessManagerLightStorage();
        return $._admin[group].union(ADMIN_MASK); // Admin have power over all groups
    }

    /// @dev Returns the requirements for the `target` and `selector`.
    function getRequirements(address target, bytes4 selector) public view returns (Masks.Mask) {
        AccessManagerLightStorage storage $ = _getAccessManagerLightStorage();
        return $._requirements[target][selector].union(ADMIN_MASK); // Admins can call an function
    }

    /// @dev Adds the `user` to the `group`. Emits {GroupAdded} event.
    function addGroup(address user, uint8 group) public onlyRole(getGroupAdmins(group)) {
        _addGroup(user, group);
    }

    /// @dev Removes the `user` from the `group`. Emits {GroupRemoved} event.
    function remGroup(address user, uint8 group) public onlyRole(getGroupAdmins(group)) {
        _remGroup(user, group);
    }

    /// @dev Internal version of {addGroup} without access control.
    function _addGroup(address user, uint8 group) internal {
        AccessManagerLightStorage storage $ = _getAccessManagerLightStorage();
        $._groups[user] = $._groups[user].union(group.toMask());
        emit GroupAdded(user, group);
    }

    /// @dev Internal version of {remGroup} without access control.
    function _remGroup(address user, uint8 group) internal {
        AccessManagerLightStorage storage $ = _getAccessManagerLightStorage();
        $._groups[user] = $._groups[user].difference(group.toMask());
        emit GroupRemoved(user, group);
    }

    /// @dev Sets the `admins` of the `group`. Emits {GroupAdmins} event.
    function setGroupAdmins(uint8 group, uint8[] calldata admins) public onlyRole(ADMIN_MASK) {
        _setGroupAdmins(group, admins.toMask());
    }

    /// @dev Internal version of {_setGroupAdmins} without access control.
    function _setGroupAdmins(uint8 group, Masks.Mask admins) internal {
        AccessManagerLightStorage storage $ = _getAccessManagerLightStorage();
        $._admin[group] = admins;
        emit GroupAdmins(group, admins);
    }

    /// @dev Sets the `groups` requirements for the `selectors` of the `target`.
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

    /// @dev Internal version of {_setRequirements} without access control.
    function _setRequirements(address target, bytes4 selector, Masks.Mask groups) internal {
        AccessManagerLightStorage storage $ = _getAccessManagerLightStorage();
        $._requirements[target][selector] = groups;
        emit RequirementsSet(target, selector, groups);
    }
}
