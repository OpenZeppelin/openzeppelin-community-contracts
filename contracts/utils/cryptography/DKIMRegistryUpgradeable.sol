// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDKIMRegistry} from "@openzeppelin/community-contracts/interfaces/IERC7969.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @dev Implementation of the https://eips.ethereum.org/EIPS/eip-7969[ERC-7969] interface for registering
 * and validating DomainKeys Identified Mail (DKIM) public key hashes onchain.
 *
 * This contract provides a standard way to register and validate DKIM public key hashes, enabling
 * email-based account abstraction and secure account recovery mechanisms. Domain owners can register
 * their DKIM public key hashes and third parties can verify their validity.
 *
 * The contract stores mappings of domain hashes to DKIM public key hashes, where:
 *
 * * Domain hash: keccak256 hash of the lowercase domain name
 * * Key hash: keccak256 hash of the DKIM public key
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyDKIMRegistry is DKIMRegistry, Ownable {
 *     function setKeyHash(bytes32 domainHash, bytes32 keyHash) public onlyOwner {
 *         _setKeyHash(domainHash, keyHash);
 *     }
 *
 *     function setKeyHashes(bytes32 domainHash, bytes32[] memory keyHashes) public onlyOwner {
 *         _setKeyHashes(domainHash, keyHashes);
 *     }
 *
 *     function revokeKeyHash(bytes32 domainHash, bytes32 keyHash) public onlyOwner {
 *         _revokeKeyHash(domainHash, keyHash);
 *     }
 * }
 * ```
 */
abstract contract DKIMRegistryUpgradeable is Initializable, IDKIMRegistry {
    /// @custom:storage-location erc7201:openzeppelin.storage.DKIMRegistry
    struct DKIMRegistryStorage {
        /// @dev Mapping from domain hash to key hash to validity status
        mapping(bytes32 domainHash => mapping(bytes32 keyHash => bool)) _keyHashes;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.DKIMRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant DKIMRegistryStorageLocation = 0x49a30c6ada2058201bfeb856e8e900ce9418ac50adefb0e3f73775372fbde100;

    function _getDKIMRegistryStorage() private pure returns (DKIMRegistryStorage storage $) {
        assembly {
            $.slot := DKIMRegistryStorageLocation
        }
    }

    function __DKIMRegistry_init() internal onlyInitializing {
    }

    function __DKIMRegistry_init_unchained() internal onlyInitializing {
    }
    /// @dev Returns whether a DKIM key hash is valid for a given domain.
    function isKeyHashValid(bytes32 domainHash, bytes32 keyHash) public view returns (bool) {
        DKIMRegistryStorage storage $ = _getDKIMRegistryStorage();
        return $._keyHashes[domainHash][keyHash];
    }

    /**
     * @dev Sets a DKIM key hash as valid for a domain. Internal version without access control.
     *
     * Emits a {KeyHashRegistered} event.
     *
     * NOTE: This function does not validate that keyHash is non-zero. Consider adding
     * validation in derived contracts if needed.
     */
    function _setKeyHash(bytes32 domainHash, bytes32 keyHash) internal {
        DKIMRegistryStorage storage $ = _getDKIMRegistryStorage();
        $._keyHashes[domainHash][keyHash] = true;
        emit KeyHashRegistered(domainHash, keyHash);
    }

    /**
     * @dev Sets multiple DKIM key hashes as valid for a domain in a single transaction.
     * Internal version without access control.
     *
     * Emits a {KeyHashRegistered} event for each key hash.
     *
     * NOTE: This function does not validate that the keyHashes array is non-empty.
     * Consider adding validation in derived contracts if needed.
     */
    function _setKeyHashes(bytes32 domainHash, bytes32[] memory keyHashes) internal {
        for (uint256 i = 0; i < keyHashes.length; ++i) {
            _setKeyHash(domainHash, keyHashes[i]);
        }
    }

    /**
     * @dev Revokes a DKIM key hash for a domain, making it invalid.
     * Internal version without access control.
     *
     * Emits a {KeyHashRevoked} event.
     */
    function _revokeKeyHash(bytes32 domainHash, bytes32 keyHash) internal {
        DKIMRegistryStorage storage $ = _getDKIMRegistryStorage();
        delete $._keyHashes[domainHash][keyHash];
        emit KeyHashRevoked(domainHash);
    }
}
