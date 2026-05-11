// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {ERC7540} from "./ERC7540.sol";

/**
 * @dev Epoch-based batch fulfillment strategy for asynchronous deposits.
 *
 * Extends {ERC7540} with a deposit flow where requests submitted during the same epoch are batched
 * together and settled at a single exchange rate when the admin closes the epoch via {_fulfillDeposit}.
 * All controllers within a fulfilled epoch receive the same pro-rata conversion from assets to shares.
 *
 * Production equivalents:
 * https://github.com/Storm-Labs-Inc/cove-contracts-core/blob/master/src/BasketToken.sol[Cove],
 * https://github.com/AmphorProtocol/asynchronous-vault/tree/main[Amphor],
 * https://github.com/hopperlabsxyz/lagoon-v0/blob/main/src/v0.5.0/ERC7540.sol[Lagoon].
 *
 * The `requestId` returned by {requestDeposit} is the epoch ID. By default, epochs are weekly
 * (`block.timestamp / 1 weeks`); override {currentDepositEpoch} to change the cadence or use
 * manually-bumped epoch counters.
 *
 * Each account tracks its epoch memberships via a {DoubleEndedQueue} capped at
 * {_requestQueueLimit} entries (default: 32) to bound the O(n) loops in {_asyncMaxDeposit}
 * and {_asyncMaxMint}. Users that hit the limit should claim fulfilled epochs to free up space.
 *
 * NOTE: Distribution within an epoch is exact. The sum of shares paid across all calls to
 * {_consumeClaimableDeposit} and {_consumeClaimableMint} equals the fulfilled `totalShares`.
 * Each claim is floor-rounded against the remaining `totalAssets` and `totalShares`, so any
 * sub-unit residue accumulates and is absorbed by the final claim in the epoch rather than
 * left stranded in the contract.
 */
abstract contract ERC7540EpochDeposit is ERC7540 {
    using Math for uint256;
    using SafeCast for uint256;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    /**
     * @dev Per-epoch deposit metadata. `totalShares` is zero while the epoch is Pending and
     * set to the minted share total when the admin calls {_fulfillDeposit}.
     */
    struct EpochDepositMetadata {
        uint256 totalAssets;
        uint256 totalShares;
        mapping(address account => uint256) requests;
    }

    mapping(uint256 epochId => EpochDepositMetadata) private _epochs;
    mapping(address account => DoubleEndedQueue.Bytes32Deque) private _memberOf;

    /// @inheritdoc ERC7540
    function _isDepositAsync() internal pure virtual override returns (bool) {
        return true;
    }

    /// @dev Returns the current epoch ID. Defaults to `block.timestamp / 1 weeks`.
    function currentDepositEpoch() public view virtual returns (uint256) {
        return block.timestamp / 1 weeks;
    }

    /// @dev A request is pending if its epoch has not yet been fulfilled (`totalShares == 0`).
    function _pendingDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        EpochDepositMetadata storage details = _epochs[requestId];
        return details.totalShares == 0 ? details.requests[controller] : 0;
    }

    /// @dev A request is claimable if its epoch has been fulfilled (`totalShares > 0`).
    function _claimableDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        EpochDepositMetadata storage details = _epochs[requestId];
        return details.totalShares == 0 ? 0 : details.requests[controller];
    }

    /**
     * @dev Sums claimable assets across all fulfilled epochs the `owner` participates in.
     *
     * NOTE: This function iterates over the `owner`'s epoch queue, which is O(n) in the number of
     * epochs the owner participates in. This is bounded by {_requestQueueLimit} (default 32) and is
     * per-account; an attacker creating many small requests can only inflate their own queue, not
     * other users'. Cross-controller DoS is not possible because epoch fulfillment via {_fulfillDeposit}
     * is O(1) (it sets `totalShares` for the entire epoch in a single write).
     */
    function _asyncMaxDeposit(address owner) internal view virtual override returns (uint256 assets) {
        uint256 result = 0;
        for (uint256 i = 0; i < _memberOf[owner].length(); ++i) {
            uint256 epochId = uint256(_memberOf[owner].at(i));
            result += _claimableDepositRequest(epochId, owner);
        }
        return result;
    }

    /// @dev Sums claimable shares across all fulfilled epochs the `owner` participates in.
    function _asyncMaxMint(address owner) internal view virtual override returns (uint256 shares) {
        uint256 result = 0;
        for (uint256 i = 0; i < _memberOf[owner].length(); ++i) {
            uint256 epochId = uint256(_memberOf[owner].at(i));
            result += Math.mulDiv(
                _claimableDepositRequest(epochId, owner),
                _epochs[epochId].totalShares,
                _epochs[epochId].totalAssets,
                Math.Rounding.Floor
            );
        }
        return result;
    }

    /**
     * @dev Records the request in the current epoch and enqueues the epoch ID for `controller`
     * if not already present.
     *
     * Requirements:
     *
     * * The controller's epoch queue must not exceed {_requestQueueLimit}.
     */
    function _requestDeposit(
        uint256 assets,
        address controller,
        address owner,
        uint256 /* requestId */
    ) internal virtual override returns (uint256) {
        uint256 epochId = currentDepositEpoch();
        _epochs[epochId].totalAssets += assets;
        _epochs[epochId].requests[controller] += assets;

        (bool success, bytes32 lastEpochId) = _memberOf[controller].tryBack();
        if (!success || lastEpochId != bytes32(epochId)) {
            // Limit the number of pending epochs per account to avoid O(n) loop in
            // _asyncMaxDeposit and _asyncMaxMint being a concern. Users that have reached
            // the limit should claim fulfilled requests to clean up the queue.
            require(_memberOf[controller].length() < _requestQueueLimit());

            _memberOf[controller].pushBack(bytes32(epochId));
        }

        return super._requestDeposit(assets, controller, owner, epochId);
    }

    /// @dev Returns the total assets available to fulfill for `epochId`, or 0 if already fulfilled or still current.
    function _assetsToFulfillDeposit(uint256 epochId) internal view virtual returns (uint256) {
        return epochId < currentDepositEpoch() && _epochs[epochId].totalShares == 0 ? _epochs[epochId].totalAssets : 0;
    }

    /**
     * @dev Fulfills a past epoch by setting its `totalShares`. All requests within the epoch
     * become claimable at the rate `totalShares / totalAssets`.
     *
     * NOTE: When epoch transition is manual, the caller should bump the epoch before calling this.
     *
     * NOTE: Pending vs. fulfilled is distinguished by `totalShares == 0`. Admins are assumed not
     * to fulfill at zero (a confiscation event with no economic purpose); if 0 is passed by
     * accident, the call is a no-op and the admin can re-fulfill. This recovery only holds as
     * long as derived contracts preserve the no-side-effect semantics of this function — if not,
     * derived contracts should restrict `totalShares != 0`.
     *
     * Requirements:
     *
     * * `epochId` must be a past epoch (less than {currentDepositEpoch}).
     * * The epoch must have pending assets and must not have been fulfilled already.
     */
    function _fulfillDeposit(uint256 epochId, uint256 totalShares) internal virtual {
        require(epochId < currentDepositEpoch()); // TODO: too early

        EpochDepositMetadata storage details = _epochs[epochId];
        require(details.totalAssets > 0 && details.totalShares == 0); // TODO: invalid resolve

        details.totalShares = totalShares;
        // TODO: emit event
    }

    /**
     * @dev Iterates through the controller's epoch queue front-to-back, consuming assets
     * and converting them to shares at each epoch's locked rate. Fully consumed epochs
     * are dequeued.
     */
    function _consumeClaimableDeposit(uint256 assets, address controller) internal virtual override returns (uint256) {
        uint256 shares = 0;

        while (assets > 0) {
            uint256 epochId = uint256(_memberOf[controller].front());

            EpochDepositMetadata storage details = _epochs[epochId];

            uint256 requested = details.requests[controller];
            if (requested <= assets) _memberOf[controller].popFront();

            uint256 batchAssets = requested.min(assets);
            uint256 batchShares = batchAssets.mulDiv(details.totalShares, details.totalAssets, Math.Rounding.Floor);

            details.requests[controller] -= batchAssets; // May need saturatingSub for rounding handling
            details.totalAssets -= batchAssets; // May need saturatingSub for rounding handling
            details.totalShares -= batchShares; // May need saturatingSub for rounding handling
            assets -= batchAssets; // May need saturatingSub for rounding handling
            shares += batchShares;
        }

        return shares;
    }

    /// @dev Same as {_consumeClaimableDeposit} but iterates by shares instead of assets.
    function _consumeClaimableMint(uint256 shares, address controller) internal virtual override returns (uint256) {
        uint256 assets = 0;

        while (shares > 0) {
            uint256 epochId = uint256(_memberOf[controller].front());

            EpochDepositMetadata storage details = _epochs[epochId];

            uint256 requested = details.requests[controller].mulDiv(
                details.totalShares,
                details.totalAssets,
                Math.Rounding.Ceil
            );
            if (requested <= shares) _memberOf[controller].popFront();

            uint256 batchShares = requested.min(shares);
            uint256 batchAssets = batchShares.mulDiv(details.totalAssets, details.totalShares, Math.Rounding.Floor);

            details.requests[controller] -= batchAssets; // May need saturatingSub for rounding handling
            details.totalAssets -= batchAssets; // May need saturatingSub for rounding handling
            details.totalShares -= batchShares; // May need saturatingSub for rounding handling
            shares -= batchShares; // May need saturatingSub for rounding handling
            assets += batchAssets;
        }

        return assets;
    }

    /**
     * @dev Maximum number of epoch entries in a controller's queue. Defaults to 32.
     * Prevents unbounded iteration in {_asyncMaxDeposit} and {_asyncMaxMint}.
     */
    function _requestQueueLimit() internal view virtual returns (uint256) {
        return 32;
    }
}
