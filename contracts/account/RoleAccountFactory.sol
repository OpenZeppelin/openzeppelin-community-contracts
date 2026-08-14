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
 * NOTE: {deployRoleAccount} is permissionless. Because the deployment is deterministic and behaviorally
 * fixed, this is harmless (front-running it only produces the same account).
 */
contract RoleAccountFactory {
    /**
     * @dev The implementation used for deploying each role account. This is set in the constructor and cannot
     * be changed.
     */
    address private immutable _implementation;

    /// @dev Emitted when a {RoleAccount} is deployed for a role on an access manager.
    event RoleAccountDeployed(address indexed accessManager, uint64 indexed roleId, address account);

    constructor() {
        _implementation = _deployImplementation();
    }

    /**
     * @dev Returns the deterministic address of the {RoleAccount} for `roleId` on `accessManager`, whether
     * or not it has already been deployed.
     */
    function getRoleAccount(address accessManager, uint64 roleId) public view virtual returns (address) {
        return
            Clones.predictDeterministicAddressWithImmutableArgs(
                _implementation,
                abi.encodePacked(accessManager, roleId),
                bytes32(0)
            );
    }

    /// @dev Returns the implementation used for deploying role accounts.
    function getImplementation() public view virtual returns (address) {
        return _implementation;
    }

    /**
     * @dev Deploys the {RoleAccount} clone for `roleId` on `accessManager` at its deterministic address and
     * returns it. Reverts if the account has already been deployed.
     */
    function deployRoleAccount(address accessManager, uint64 roleId) public virtual returns (address) {
        address roleAccount = Clones.cloneDeterministicWithImmutableArgs(
            _implementation,
            abi.encodePacked(accessManager, roleId),
            bytes32(0)
        );
        emit RoleAccountDeployed(accessManager, roleId, roleAccount);

        return roleAccount;
    }

    /**
     * @dev Called once during construction to get the implementation used for deploying role accounts.
     * Can be overridden to provide a custom implementation.
     */
    function _deployImplementation() internal virtual returns (address) {
        return address(new RoleAccount());
    }
}
