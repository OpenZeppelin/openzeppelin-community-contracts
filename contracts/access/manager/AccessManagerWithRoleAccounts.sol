// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {RoleAccount} from "../../account/RoleAccount.sol";

/**
 * @dev Extension of {AccessManager} that exposes a deterministic {RoleAccount} for each role.
 *
 * Every role managed by this instance has an associated {RoleAccount} deployed at an address derived
 * deterministically from the role id. That account acts on behalf of the current members of the role:
 * it can produce ERC-1271 signatures and execute batched calls, and its authority follows role
 * membership as it is granted or revoked through the access manager.
 *
 * The account address can be computed off-chain (or on-chain via {getRoleAccount}) before deployment,
 * so it can be used as an authorization target or funded ahead of time. {deployRoleAccount} materializes
 * the clone at that address when needed.
 *
 * WARNING: A role account grants control to *every current member* of its role. For the special
 * `PUBLIC_ROLE` (`type(uint64).max`), which every address belongs to, this means the account is
 * controllable by anyone; the `ADMIN_ROLE` account is likewise controllable by any admin. Do not fund
 * these accounts or grant them authority unless that shared/open control is intended.
 *
 * NOTE: {deployRoleAccount} is permissionless. Because the deployment is deterministic and behaviorally
 * fixed, this is harmless (front-running it only produces the same account), but it means an account may
 * exist for a role before it is configured.
 */
contract AccessManagerWithRoleAccounts is AccessManager {
    /// @dev Implementation cloned (with the role id as immutable args) to produce each {RoleAccount}.
    address private immutable _template = address(new RoleAccount(this));

    /// @param initialAdmin The address granted the `ADMIN_ROLE` of the access manager.
    constructor(address initialAdmin) AccessManager(initialAdmin) {}

    /**
     * @dev Returns the deterministic address of the {RoleAccount} for `roleId`, whether or not it has
     * already been deployed.
     * @param roleId The role whose account address is computed.
     * @return The address at which the role's {RoleAccount} lives (once deployed).
     */
    function getRoleAccount(uint64 roleId) public view returns (address) {
        return
            Clones.predictDeterministicAddressWithImmutableArgs(
                _template,
                abi.encodePacked(roleId),
                _roleToSalt(roleId)
            );
    }

    /**
     * @dev Deploys the {RoleAccount} clone for `roleId` at its deterministic address and returns it.
     * Reverts if the account for `roleId` has already been deployed.
     * @param roleId The role to deploy an account for.
     * @return The address of the newly deployed {RoleAccount}.
     */
    function deployRoleAccount(uint64 roleId) public returns (address) {
        return Clones.cloneDeterministicWithImmutableArgs(_template, abi.encodePacked(roleId), _roleToSalt(roleId));
    }

    /**
     * @dev Derives the CREATE2 salt used to deploy the clone for `roleId`. Defaults to the role id
     * itself; override to customize the salt derivation.
     * @param roleId The role whose salt is derived.
     * @return The CREATE2 salt for the role's clone.
     */
    function _roleToSalt(uint64 roleId) internal view virtual returns (bytes32) {
        return bytes32(uint256(roleId));
    }
}
