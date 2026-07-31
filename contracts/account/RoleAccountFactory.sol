// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {RoleAccount} from "./RoleAccount.sol";

/**
 * @dev Factory that exposes a deterministic {RoleAccount} for each role of an {IAccessManager}.
 *
 * The factory is bound to an external {accessManager} at construction (rather than being one), so it can
 * be attached to an already-deployed manager without redeploying it. Every role of that manager has an
 * associated {RoleAccount} deployed at an address derived deterministically from the role id. That
 * account acts on behalf of the current members of the role: it can produce ERC-1271 signatures and
 * execute batched calls, and its authority follows role membership as it is granted or revoked through
 * the access manager.
 *
 * The account address can be computed off-chain (or on-chain via {getRoleAccount}) before deployment,
 * so it can be used as an authorization target or funded ahead of time. {deployRoleAccount} materializes
 * the clone at that address when needed.
 *
 * NOTE: Addresses are deterministic per factory (they depend on this factory's {_template}). Integrators
 * that rely on a canonical `role -> account` mapping should treat a single factory as the source of
 * truth for a given {accessManager}.
 *
 * WARNING: A role account grants control to *every current member* of its role. For the special
 * `PUBLIC_ROLE` (`type(uint64).max`), which every address belongs to, this means the account is
 * controllable by anyone.
 *
 * NOTE: {deployRoleAccount} is permissionless. Because the deployment is deterministic and behaviorally
 * fixed, this is harmless (front-running it only produces the same account).
 */
contract RoleAccountFactory {
    /// @dev The access manager whose roles the deployed {RoleAccount}s are bound to.
    IAccessManager public immutable accessManager;

    /// @dev Implementation cloned (with the role id as immutable args) to produce each {RoleAccount}.
    address private immutable _template;

    /**
     * @dev Binds this factory to `accessManager_` and deploys the {RoleAccount} implementation that is
     * cloned per role. A zero `accessManager_` reverts through {RoleSigner}'s constructor.
     */
    constructor(IAccessManager accessManager_) {
        accessManager = accessManager_;
        _template = address(new RoleAccount(accessManager_));
    }

    /**
     * @dev Returns the deterministic address of the {RoleAccount} for `roleId`, whether or not it has
     * already been deployed.
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
     */
    function deployRoleAccount(uint64 roleId) public returns (address) {
        return Clones.cloneDeterministicWithImmutableArgs(_template, abi.encodePacked(roleId), _roleToSalt(roleId));
    }

    /**
     * @dev Derives the CREATE2 salt used to deploy the clone for `roleId`. Defaults to the role id
     * itself.
     */
    function _roleToSalt(uint64 roleId) internal view virtual returns (bytes32) {
        return bytes32(uint256(roleId));
    }
}
