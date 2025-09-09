// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDKIMRegistry} from "../../interfaces/IERC7969.sol";

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
abstract contract DKIMRegistry is IDKIMRegistry {
    /// @dev Mapping from domain hash to key hash to validity status
    mapping(bytes32 domainHash => mapping(bytes32 keyHash => bool)) private _keyHashes;

    /// @dev Returns whether a DKIM key hash is valid for a given domain.
    function isKeyHashValid(bytes32 domainHash, bytes32 keyHash) public view returns (bool) {
        return _keyHashes[domainHash][keyHash];
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
        _keyHashes[domainHash][keyHash] = true;
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
        delete _keyHashes[domainHash][keyHash];
        emit KeyHashRevoked(domainHash);
    }
}
