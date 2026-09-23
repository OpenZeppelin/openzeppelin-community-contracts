// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PrivateLedger} from "./PrivateLedger.sol";

/**
 * @dev Library for implementing spendable private notes.
 *
 * Private notes represent discrete units of value that can be spent exactly once, building
 * on the {PrivateLedger} foundation with opinionated spending functionality. This library adds
 * double-spend prevention, lineage tracking options, and transaction-like operations for
 * creating privacy-focused token systems, mixers, and confidential transfer protocols.
 */
library PrivateNote {
    using PrivateLedger for PrivateLedger.Entry;

    /**
     * @dev Struct to represent a privacy-preserving spendable note
     *
     * Builds on {PrivateLedger-Entry} to add spending functionality without lineage tracking.
     * The `spent` flag prevents double-spending while maintaining maximum privacy by not
     * storing parent note references. Uses bytes32 for maximum flexibility with encrypted
     * values, commitments, or plaintext amounts.
     */
    struct SpendableBytes32 {
        PrivateLedger.Entry entry; // Underlying ledger entry
        bool spent; // Prevents double-spending
    }

    /**
     * @dev Struct to represent a trackable spendable note with lineage
     *
     * Builds on {PrivateLedger-Entry} to add spending functionality with lineage tracking.
     * The `spent` flag prevents double-spending while `createdBy` enables transaction chain
     * reconstruction for auditability. Reduces privacy but enables compliance scenarios.
     */
    struct TrackableSpendableBytes32 {
        PrivateLedger.Entry entry; // Underlying ledger entry
        bool spent; // Prevents double-spending
        bytes32 createdBy; // ID of parent note for lineage tracking
    }

    /// @dev Emitted when a new privacy-preserving spendable note is created
    event SpendableBytes32Created(bytes32 indexed id, address indexed owner, bytes32 value);

    /// @dev Emitted when a privacy-preserving spendable note is spent
    event SpendableBytes32Spent(bytes32 indexed id, address indexed spender);

    /// @dev Emitted when a new trackable spendable note is created
    event TrackableSpendableBytes32Created(bytes32 indexed id, address indexed owner, bytes32 value, bytes32 createdBy);

    /// @dev Emitted when a trackable spendable note is spent
    event TrackableSpendableBytes32Spent(bytes32 indexed id, address indexed spender);

    /**
     * @dev Creates a new privacy-preserving spendable note
     *
     * Creates a note without parent lineage tracking for maximum privacy. The note can be
     * spent exactly once using the spend function. Use this for privacy-focused applications
     * where transaction unlinkability is prioritized over auditability.
     */
    function create(SpendableBytes32 storage note, address owner, bytes32 value, bytes32 id) internal {
        note.entry.create(owner, value);
        // note.spent = false; // false by default

        emit SpendableBytes32Created(id, owner, value);
    }

    /**
     * @dev Creates a new trackable spendable note with lineage
     *
     * Creates a note with parent linkage for auditability. The `createdBy` field allows
     * transaction chain reconstruction but reduces privacy. Use this for compliance
     * scenarios or when transaction history tracking is required.
     */
    function create(
        TrackableSpendableBytes32 storage note,
        address owner,
        bytes32 value,
        bytes32 id,
        bytes32 parentId
    ) internal {
        note.entry.create(owner, value);
        note.createdBy = parentId; // Enables lineage tracking
        // note.spent = false; // false by default

        emit TrackableSpendableBytes32Created(id, owner, value, parentId);
    }

    /**
     * @dev Spends a privacy-preserving note
     *
     * Spends the note while maintaining maximum privacy. The spent note cannot be used
     * again. External note creation should use SpendableBytes32 to maintain privacy.
     */
    function spend(
        SpendableBytes32 storage note,
        bytes32 noteId,
        bytes32 recipientId,
        bytes32 changeId
    ) internal returns (bytes32 actualRecipientId, bytes32 actualChangeId) {
        require(!note.spent, "PrivateNote: already spent");
        require(note.entry.owner != address(0), "PrivateNote: note does not exist");

        note.spent = true;
        emit SpendableBytes32Spent(noteId, note.entry.owner);

        // Return the provided IDs for external note creation
        return (recipientId, changeId);
    }

    /**
     * @dev Spends a trackable note with lineage preservation
     *
     * Spends the note while maintaining transaction history through parent linkage.
     * External note creation should use TrackableSpendableBytes32 with this note's ID
     * as the parent to maintain the audit trail.
     */
    function spend(
        TrackableSpendableBytes32 storage note,
        bytes32 noteId,
        bytes32 recipientId,
        bytes32 changeId
    ) internal returns (bytes32 actualRecipientId, bytes32 actualChangeId) {
        require(!note.spent, "PrivateNote: already spent");
        require(note.entry.owner != address(0), "PrivateNote: note does not exist");

        note.spent = true;
        emit TrackableSpendableBytes32Spent(noteId, note.entry.owner);

        // Return the provided IDs for external trackable note creation
        return (recipientId, changeId);
    }

    /**
     * @dev Checks if a privacy-preserving note exists and is unspent
     */
    function isUnspent(SpendableBytes32 storage note) internal view returns (bool) {
        return note.entry.exists() && !note.spent;
    }

    /**
     * @dev Checks if a privacy-preserving note exists (regardless of spent status)
     */
    function exists(SpendableBytes32 storage note) internal view returns (bool) {
        return note.entry.exists();
    }

    /**
     * @dev Checks if a trackable note exists and is unspent
     */
    function isUnspent(TrackableSpendableBytes32 storage note) internal view returns (bool) {
        return note.entry.exists() && !note.spent;
    }

    /**
     * @dev Checks if a trackable note exists (regardless of spent status)
     */
    function exists(TrackableSpendableBytes32 storage note) internal view returns (bool) {
        return note.entry.exists();
    }
}
