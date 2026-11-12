// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {RoleAccountUpgradeable} from "./RoleAccountUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

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
contract RoleAccountFactoryUpgradeable is Initializable {
    /// @custom:storage-location erc7201:openzeppelin.storage.RoleAccountFactory
    struct RoleAccountFactoryStorage {
        /**
         * @dev The implementation used for deploying each role account. This is set in the constructor and cannot
         * be changed.
         */
        address _implementation;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.RoleAccountFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant RoleAccountFactoryStorageLocation = 0x450ffbb4ef027f3062bb163788e5f2fa0809badc79e9921f7ef1dad45ac1a600;

    function _getRoleAccountFactoryStorage() private pure returns (RoleAccountFactoryStorage storage $) {
        assembly {
            $.slot := RoleAccountFactoryStorageLocation
        }
    }

    /// @dev Emitted when a {RoleAccount} is deployed for a role on an access manager.
    event RoleAccountDeployed(address indexed accessManager, uint64 indexed roleId, address account);

    function initialize() public virtual initializer {
        __RoleAccountFactory_init();
    }
    function __RoleAccountFactory_init() internal onlyInitializing {
        __RoleAccountFactory_init_unchained();
    }

    function __RoleAccountFactory_init_unchained() internal onlyInitializing {
        RoleAccountFactoryStorage storage $ = _getRoleAccountFactoryStorage();
        $._implementation = _deployImplementation();
    }

    /**
     * @dev Returns the deterministic address of the {RoleAccount} for `roleId` on `accessManager`, whether
     * or not it has already been deployed.
     */
    function getRoleAccount(address accessManager, uint64 roleId) public view virtual returns (address) {
        RoleAccountFactoryStorage storage $ = _getRoleAccountFactoryStorage();
        return
            Clones.predictDeterministicAddressWithImmutableArgs(
                $._implementation,
                abi.encodePacked(accessManager, roleId),
                bytes32(0)
            );
    }

    /// @dev Returns the implementation used for deploying role accounts.
    function getImplementation() public view virtual returns (address) {
        RoleAccountFactoryStorage storage $ = _getRoleAccountFactoryStorage();
        return $._implementation;
    }

    /**
     * @dev Deploys the {RoleAccount} clone for `roleId` on `accessManager` at its deterministic address and
     * returns it. Reverts if the account has already been deployed.
     */
    function deployRoleAccount(address accessManager, uint64 roleId) public virtual returns (address) {
        RoleAccountFactoryStorage storage $ = _getRoleAccountFactoryStorage();
        address roleAccount = Clones.cloneDeterministicWithImmutableArgs(
            $._implementation,
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
        return address(new RoleAccountUpgradeable());
    }
}
