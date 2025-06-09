// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Library for implementing Unspent Transaction Outputs (UTXOs).
 *
 * UTXOs represent discrete units of value that can be spent exactly once. This minimal design
 * uses bytes32 for values to support multiple value representations: plaintext amounts,
 * encrypted values (FHE), zero-knowledge commitments, or other privacy-preserving formats.
 */
library UTXOs {
    /**
     * @dev Struct to represent a UTXO (Unspent Transaction Output)
     *
     * Uses bytes32 for the value to maximize flexibility. This allows the library to work with:
     *
     * * Regular uint256 values (cast to `bytes32`)
     * * FHE encrypted value pointers (`euint64.unwrap()`)
     * * Zero-knowledge commitments (commitment hashes)
     * * Other privacy-preserving value representations
     */
    struct Note {
        address owner; // Owner of the note
        bytes32 value; // Generic value representation
    }

    /**
     * @dev Creates a new note with the specified owner and value
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
    function create(Note storage note, address owner, bytes32 value) internal {
        require(note.owner == address(0), "Notes: ID already exists");
        note.owner = owner;
        note.value = value;
    }

    /**
     * @dev Checks if a note exists
     *
     * Uses the owner field as existence indicator since zero address
     * is not a valid owner for active notes.
     */
    function exists(Note storage note) internal view returns (bool) {
        return note.owner != address(0);
    }

    /**
     * @dev Deletes a note from storage
     *
     * Removes the note completely. Developers should implement their own
     * authorization checks and update index mappings before calling this function.
     */
    function remove(Note storage note) internal {
        require(note.owner != address(0), "UTXOs: note does not exist");
        note.owner = address(0);
        note.value = bytes32(0);
    }

    /**
     * @dev Transfers a note to a new owner
     *
     * Allows ownership transfers. Developers should implement authorization
     * checks to ensure only the current owner or authorized parties can
     * transfer ownership.
     *
     * NOTE: Does not verify `to != address(0)`. Transferring to the zero
     * address may leave the value of the note unspent. Consider using
     * {remove} instead.
     */
    function transfer(Note storage note, address to) internal {
        require(note.owner != address(0), "UTXOs: note does not exist");
        note.owner = to;
    }

    /**
     * @dev Updates the value of an existing note
     *
     * Allows value modifications for specific use cases. Developers should
     * implement proper authorization checks before calling this function.
     * Useful for encrypted value updates or commitment reveals.
     */
    function update(Note storage note, bytes32 newValue) internal {
        require(note.owner != address(0), "UTXOs: note does not exist");
        note.value = newValue;
    }
}
