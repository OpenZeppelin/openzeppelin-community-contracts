// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Library for implementing private ledger entries.
 *
 * Private ledger entries represent discrete units of value with flexible representation.
 * This minimal design uses bytes32 for values to support multiple value representations:
 * plaintext amounts, encrypted values (FHE), zero-knowledge commitments, or other
 * privacy-preserving formats. The library provides basic primitives for creating,
 * transferring, and managing entries without imposing specific spending semantics.
 */
library PrivateLedger {
    /**
     * @dev Struct to represent a private ledger entry
     *
     * Uses bytes32 for the value to maximize flexibility. This allows the library to work with:
     *
     * * Regular uint256 values (cast to `bytes32`)
     * * FHE encrypted value pointers (`euint64.unwrap()`)
     * * Zero-knowledge commitments (commitment hashes)
     * * Other privacy-preserving value representations
     */
    struct Entry {
        bytes32 value; // Generic value representation
        address owner; // Owner of the entry
    }

    /**
     * @dev Creates a new entry with the specified owner and value
     *
     * The value parameter can represent different formats depending on the use case:
     *
     * * Plaintext: `bytes32(uint256(value))`
     * * FHE encrypted: `euint64.unwrap(encryptedAmount)`
     * * ZK commitment: `keccak256(abi.encode(value, nonce))`
     *
     * NOTE: Does not verify `owner != address(0)` or that value is not zero as it
     * has a different meaning depending on the context. Consider implementing checks
     * before using this function.
     */
    function create(Entry storage entry, address owner, bytes32 value) internal {
        require(entry.owner == address(0));
        entry.owner = owner;
        entry.value = value;
    }

    /**
     * @dev Checks if an entry exists
     *
     * Uses the owner field as existence indicator since zero address
     * is not a valid owner for active entries.
     */
    function exists(Entry storage entry) internal view returns (bool) {
        return entry.owner != address(0);
    }

    /**
     * @dev Deletes an entry from storage
     *
     * Removes the entry completely. Developers should implement their own
     * authorization checks and update index mappings before calling this function.
     */
    function remove(Entry storage entry) internal {
        require(entry.owner != address(0));
        entry.owner = address(0);
        entry.value = bytes32(0);
    }

    /**
     * @dev Transfers an entry to a new owner
     *
     * Allows ownership transfers. Developers should implement authorization
     * checks to ensure only the current owner or authorized parties can
     * transfer ownership.
     *
     * NOTE: Does not verify `to != address(0)`. Transferring to the zero
     * address may leave the value of the entry unspent. Consider using
     * {remove} instead.
     */
    function transfer(Entry storage entry, address to) internal {
        require(entry.owner != address(0));
        entry.owner = to;
    }

    /**
     * @dev Updates the value of an existing entry
     *
     * Allows value modifications for specific use cases. Developers should
     * implement proper authorization checks before calling this function.
     * Useful for encrypted value updates or commitment reveals.
     */
    function update(Entry storage entry, bytes32 newValue) internal {
        require(entry.owner != address(0));
        entry.value = newValue;
    }
}
