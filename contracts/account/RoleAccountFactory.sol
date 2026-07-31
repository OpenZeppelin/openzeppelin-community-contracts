// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {RoleAccount} from "./RoleAccount.sol";

/**
 * @dev Factory for building {RoleAccount} for any role of any access manager.
 *
 * Each (access manager, role) pair has an associated {RoleAccount} deployed at an address derived
 * deterministically from that pair. That account acts on behalf of the current members of the role:
 * it can produce ERC-1271 signatures and execute batched calls, and its authority follows role
 * membership as it is granted or revoked through the access manager.
 *
 * The account address can be computed off-chain (or on-chain via {getRoleAccount}) before deployment,
 * so it can be used as an authorization target or funded ahead of time. {deployRoleAccount} materializes
 * the clone at that address when needed.
 *
 * WARNING: A role account grants control to *every current member* of its role. For the special
 * `PUBLIC_ROLE` (`type(uint64).max`), which every address belongs to, this means the account is
 * controllable by anyone.
 *
 * NOTE: {deployRoleAccount} is permissionless. Because the deployment is deterministic and behaviorally
 * fixed, this is harmless (front-running it only produces the same account).
 */
contract RoleAccountFactory {
    /// @dev Implementation cloned (with the access manager and role id as immutable args) to produce each {RoleAccount}.
    RoleAccount private immutable _template = new RoleAccount();

    /// @dev Emitted when a {RoleAccount} is deployed for a role on an access manager.
    event RoleAccountDeployed(address indexed accessManager, uint64 indexed roleId, address account);

    /**
     * @dev Returns the deterministic address of the {RoleAccount} for `roleId` on `accessManager`, whether
     * or not it has already been deployed.
     */
    function getRoleAccount(address accessManager, uint64 roleId) public view virtual returns (address) {
        return
            Clones.predictDeterministicAddressWithImmutableArgs(
                address(_template),
                abi.encodePacked(accessManager, roleId),
                bytes32(0)
            );
    }

    /**
     * @dev Deploys the {RoleAccount} clone for `roleId` on `accessManager` at its deterministic address and
     * returns it. Reverts if the account has already been deployed.
     */
    function deployRoleAccount(address accessManager, uint64 roleId) public virtual returns (address) {
        address roleAccount = Clones.cloneDeterministicWithImmutableArgs(
            address(_template),
            abi.encodePacked(accessManager, roleId),
            bytes32(0)
        );
        emit RoleAccountDeployed(accessManager, roleId, roleAccount);

        return roleAccount;
    }
}
