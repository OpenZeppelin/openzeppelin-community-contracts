// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {ERC7540} from "./ERC7540.sol";

/**
 * @dev Epoch-based batch fulfillment strategy for asynchronous redemptions.
 *
 * Extends {ERC7540} with a redeem flow where requests submitted during the same epoch are batched
 * together and settled at a single exchange rate when the admin closes the epoch via {_fulfillRedeem}.
 * All controllers within a fulfilled epoch receive the same pro-rata conversion from shares to assets.
 *
 * Production equivalents:
 * https://github.com/Storm-Labs-Inc/cove-contracts-core/blob/master/src/BasketToken.sol[Cove],
 * https://github.com/AmphorProtocol/asynchronous-vault/tree/main[Amphor],
 * https://github.com/hopperlabsxyz/lagoon-v0/blob/main/src/v0.5.0/ERC7540.sol[Lagoon].
 *
 * The `requestId` returned by {requestRedeem} is the epoch ID. By default, epochs are weekly
 * (`block.timestamp / 1 weeks`); override {currentRedeemEpoch} to change the cadence or use
 * manually-bumped epoch counters.
 *
 * Each account tracks its epoch memberships via a {DoubleEndedQueue} capped at
 * {_requestQueueLimit} entries (default: 32) to bound the O(n) loops in {_asyncMaxWithdraw}
 * and {_asyncMaxRedeem}. Users that hit the limit should claim fulfilled epochs to free up space.
 *
 * NOTE: Claims pay each controller's pro-rata share floor-rounded against the remaining epoch
 * totals. With very small fulfillment values (e.g. an epoch settling 3 shares for 2 assets
 * across 3 equal claimants), rounding can leave one controller with up to 1 "wei" of
 * unclaimable residue. At realistic ERC-20 token decimals this is sub-unit and economically
 * immaterial. Unlike ERC-4626's inflation-attack surface, the per-epoch `totalShares` and
 * `totalAssets` cannot be inflated by donation (they only change via {requestRedeem} and
 * {_fulfillRedeem}); deployers wanting finer per-claim granularity can set {_decimalsOffset}
 * to scale share precision relative to assets.
 */
abstract contract ERC7540EpochRedeem is ERC7540 {
    using Math for uint256;
    using SafeCast for uint256;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    /**
     * @dev Per-epoch redeem metadata. `totalAssets` is zero while the epoch is Pending and
     * set to the distributed asset total when the admin calls {_fulfillRedeem}.
     */
    struct EpochRedeemMetadata {
        uint256 totalShares;
        uint256 totalAssets;
        mapping(address account => uint256) requests;
    }

    mapping(uint256 epochId => EpochRedeemMetadata) private _epochs;
    mapping(address account => DoubleEndedQueue.Bytes32Deque) private _memberOf;

    /// @dev Emitted when a redeem epoch transitions from Pending to Claimable via {_fulfillRedeem}.
    event ERC7540EpochRedeemFulfilled(uint256 indexed epochId, uint256 totalShares, uint256 totalAssets);

    /// @dev Attempted to fulfill a redeem epoch that has not yet ended.
    error ERC7540EpochRedeemTooEarly(uint256 epochId);

    /// @dev Attempted to fulfill a redeem epoch with no pending requests.
    error ERC7540EpochRedeemEmptyEpoch(uint256 epochId);

    /// @dev Attempted to fulfill a redeem epoch that has already been fulfilled.
    error ERC7540EpochRedeemAlreadyFulfilled(uint256 epochId);

    /// @dev Attempted to enqueue an epoch for `controller` past {_requestQueueLimit}.
    error ERC7540EpochRedeemQueueLimitExceeded(address controller);

    /// @inheritdoc ERC7540
    function _isRedeemAsync() internal pure virtual override returns (bool) {
        return true;
    }

    /// @dev Returns the current epoch ID. Defaults to `block.timestamp / 1 weeks`.
    function currentRedeemEpoch() public view virtual returns (uint256) {
        return block.timestamp / 1 weeks;
    }

    /**
     * @dev Returns the total shares queued in `epochId`. Equals the sum of all redeem requests
     * during the Pending phase; decreases as claimants consume their pro-rata share once the
     * epoch is fulfilled, and reaches 0 once the epoch is fully claimed.
     */
    function totalRedeemShares(uint256 epochId) public view virtual returns (uint256) {
        return _epochs[epochId].totalShares;
    }

    /**
     * @dev Returns the assets allocated to `epochId` at fulfillment. Zero before
     * {_fulfillRedeem} is called; decreases as claimants consume their pro-rata share.
     * Together with {totalRedeemShares} it encodes the locked epoch rate.
     */
    function totalRedeemAssets(uint256 epochId) public view virtual returns (uint256) {
        return _epochs[epochId].totalAssets;
    }

    /**
     * @dev Returns the redeem epoch IDs that `controller` has open requests in, in queue order
     * (oldest first). Fully claimed epochs are popped from the queue and no longer appear.
     *
     * Using `start = 0` and `end = type(uint64).max` will return the entire set of epochs.
     */
    function redeemEpochs(
        address controller,
        uint256 start,
        uint256 end
    ) public view virtual returns (uint256[] memory epochIds) {
        bytes32[] memory store = _memberOf[controller].values(start, end);
        assembly ("memory-safe") {
            epochIds := store
        }
    }

    /**
     * @dev A request is pending if its epoch has not yet been fulfilled (`totalAssets == 0`) and
     * still has shares queued (`totalShares > 0`).
     */
    function _pendingRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        return totalRedeemAssets(requestId) == 0 ? _pendingAvailableRedeemRequest(requestId, controller) : 0;
    }

    /**
     * @dev Returns the controller's stored redeem request for `requestId`, or 0 if the epoch
     * has been fully claimed (`totalShares == 0`).
     */
    function _pendingAvailableRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual returns (uint256) {
        return totalRedeemShares(requestId) == 0 ? 0 : _epochs[requestId].requests[controller];
    }

    /// @dev A request is claimable if its epoch has been fulfilled (`totalAssets > 0`).
    function _claimableRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        return totalRedeemAssets(requestId) == 0 ? 0 : _epochs[requestId].requests[controller];
    }

    /**
     * @dev Sums claimable assets from `owner`'s fulfilled epochs oldest-first, stopping at the
     * first Pending epoch. Fulfilled epochs behind a Pending one are not counted until the
     * Pending one is fulfilled. Matches {_consumeClaimableWithdraw}.
     *
     * NOTE: O(n) in `owner`'s epochs, bounded by {_requestQueueLimit} (default 32). Per-account,
     * so an attacker creating many small requests can only inflate their own queue, not
     * other users'. Cross-controller DoS is not possible because epoch fulfillment via
     * {_fulfillRedeem} is O(1) (it sets `totalAssets` for the entire epoch in a single write).
     */
    function _asyncMaxWithdraw(address owner) internal view virtual override returns (uint256 assets) {
        uint256 result = 0;
        for (uint256 i = 0; i < _memberOf[owner].length(); ++i) {
            uint256 epochId = uint256(_memberOf[owner].at(i));
            if (totalRedeemAssets(epochId) == 0) break; // stop at the oldest Pending epoch
            result += _convertToRedeemAssets(epochId, _claimableRedeemRequest(epochId, owner), Math.Rounding.Floor);
        }
        return result;
    }

    /// @dev Sums claimable shares across all fulfilled epochs the `owner` participates in. Same as {_asyncMaxWithdraw}.
    function _asyncMaxRedeem(address owner) internal view virtual override returns (uint256 shares) {
        uint256 result = 0;
        for (uint256 i = 0; i < _memberOf[owner].length(); ++i) {
            uint256 epochId = uint256(_memberOf[owner].at(i));
            if (totalRedeemAssets(epochId) == 0) break; // stop at the oldest Pending epoch
            result += _claimableRedeemRequest(epochId, owner);
        }
        return result;
    }

    /// @dev Converts `shares` to assets at `epochId`'s locked rate. Returns 0 if `totalShares` is 0.
    function _convertToRedeemAssets(
        uint256 epochId,
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual returns (uint256) {
        // An epoch's `totalShares` may be 0 while some `requests[*]` slots are non-zero,
        // when other controllers' asset-driven claims ({_consumeClaimableWithdraw}) round
        // `requested` up via ceil and the saturating decrement zeroes the shared pool
        // before all per-controller residues are allocated.
        uint256 totalShares = totalRedeemShares(epochId);
        return totalShares == 0 ? 0 : shares.mulDiv(totalRedeemAssets(epochId), totalShares, rounding);
    }

    /// @dev Converts `assets` to shares at `epochId`'s locked rate. Returns 0 if `totalAssets` is 0.
    function _convertToRedeemShares(
        uint256 epochId,
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual returns (uint256) {
        // An epoch's `totalAssets` may be 0 while some `requests[*]` slots are non-zero,
        // when other controllers' asset-driven claims ({_consumeClaimableWithdraw}) round
        // `requested` up via ceil and the saturating decrement zeroes the shared pool
        // before all per-controller residues are allocated.
        uint256 totalAssets = totalRedeemAssets(epochId);
        return totalAssets == 0 ? 0 : assets.mulDiv(totalRedeemShares(epochId), totalAssets, rounding);
    }

    /**
     * @dev Records the request in the current epoch and enqueues the epoch ID for `controller`
     * if not already present.
     *
     * Requirements:
     *
     * * The controller's epoch queue must not exceed {_requestQueueLimit}.
     */
    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner,
        uint256 /* requestId */
    ) internal virtual override returns (uint256) {
        uint256 epochId = currentRedeemEpoch();
        _epochs[epochId].totalShares += shares;
        _epochs[epochId].requests[controller] += shares;

        (bool success, bytes32 lastEpochId) = _memberOf[controller].tryBack();
        if (!success || lastEpochId != bytes32(epochId)) {
            // Limit the number of pending epochs per account to avoid O(n) loop in
            // _asyncMaxWithdraw and _asyncMaxRedeem being a concern. Users that have reached
            // the limit should claim fulfilled requests to clean up the queue.
            require(
                _memberOf[controller].length() < _requestQueueLimit(),
                ERC7540EpochRedeemQueueLimitExceeded(controller)
            );

            _memberOf[controller].pushBack(bytes32(epochId));
        }

        return super._requestRedeem(shares, controller, owner, epochId);
    }

    /**
     * @dev Fulfills a past epoch by setting its `totalAssets`. All requests within the epoch
     * become claimable at the rate `totalAssets / totalShares`.
     *
     * NOTE: When epoch transition is manual, the caller should bump the epoch before calling this.
     *
     * NOTE: Pending vs. fulfilled is distinguished by `totalAssets == 0`. Admins are assumed not
     * to fulfill at zero (a confiscation event with no economic purpose); if 0 is passed by
     * accident, the call is a no-op and the admin can re-fulfill. This recovery only holds as
     * long as derived contracts preserve the no-side-effect semantics of this function — if not,
     * derived contracts should restrict `totalAssets != 0`.
     *
     * NOTE: Out-of-order fulfillment is permitted, but each controller's claims stay gated on
     * their oldest Pending epoch (see {_consumeClaimableWithdraw}). Funds are not lost; a later
     * fulfilled epoch simply waits until the older one is fulfilled. Derived contracts wanting
     * strict FIFO settlement should enforce it here.
     *
     * Requirements:
     *
     * * `epochId` must be a past epoch (less than {currentRedeemEpoch}).
     * * The epoch must have pending shares and must not have been fulfilled already.
     */
    function _fulfillRedeem(uint256 epochId, uint256 totalAssets) internal virtual {
        require(epochId < currentRedeemEpoch(), ERC7540EpochRedeemTooEarly(epochId));

        uint256 totalShares = totalRedeemShares(epochId);
        require(totalShares > 0, ERC7540EpochRedeemEmptyEpoch(epochId));
        require(totalRedeemAssets(epochId) == 0, ERC7540EpochRedeemAlreadyFulfilled(epochId));

        _epochs[epochId].totalAssets = totalAssets;
        emit ERC7540EpochRedeemFulfilled(epochId, totalShares, totalAssets);
    }

    /**
     * @dev Consumes `assets` from `controller`'s epochs oldest-first at each epoch's locked rate,
     * dequeueing fully consumed ones. Breaks early when the oldest epoch is still Pending:
     * consuming from it would burn `assets` for zero shares. Claims are therefore gated on the
     * oldest Pending epoch, matching {_asyncMaxWithdraw}.
     *
     * NOTE: Wrappers wanting stricter FIFO semantics should override to revert
     * when the oldest epoch is Pending.
     */
    function _consumeClaimableWithdraw(uint256 assets, address controller) internal virtual override returns (uint256) {
        uint256 shares = 0;

        while (assets > 0) {
            uint256 epochId = uint256(_memberOf[controller].front());
            if (totalRedeemAssets(epochId) == 0) break; // oldest queued epoch is still Pending

            uint256 requestedShares = _pendingAvailableRedeemRequest(epochId, controller);
            uint256 requested = _convertToRedeemAssets(epochId, requestedShares, Math.Rounding.Ceil);
            if (requested <= assets) _memberOf[controller].popFront();

            uint256 batchAssets = requested.min(assets);
            uint256 batchShares = _convertToRedeemShares(epochId, batchAssets, Math.Rounding.Floor);

            EpochRedeemMetadata storage details = _epochs[epochId];
            // Using `requestedShares` (zero in the fully-claimed state) clears stuck dust.
            // The saturation absorbs the 1-wei ceil/floor excess in `batchShares` when fully
            // claimed, so `totalShares` reduces to 0 cleanly and the {_fulfillRedeem} sentinel
            // stays unambiguous.
            details.requests[controller] = requestedShares.saturatingSub(batchShares);
            details.totalAssets = totalRedeemAssets(epochId).saturatingSub(batchAssets);
            details.totalShares = totalRedeemShares(epochId).saturatingSub(batchShares);
            assets -= batchAssets; // batchAssets <= assets (via .min)
            shares += batchShares;
        }

        return shares;
    }

    /// @dev Same as {_consumeClaimableWithdraw} but iterates by shares instead of assets.
    function _consumeClaimableRedeem(uint256 shares, address controller) internal virtual override returns (uint256) {
        uint256 assets = 0;

        while (shares > 0) {
            uint256 epochId = uint256(_memberOf[controller].front());
            if (totalRedeemAssets(epochId) == 0) break; // oldest queued epoch is still Pending

            uint256 requested = _pendingAvailableRedeemRequest(epochId, controller);
            if (requested <= shares) _memberOf[controller].popFront();

            uint256 batchShares = requested.min(shares);
            uint256 batchAssets = _convertToRedeemAssets(epochId, batchShares, Math.Rounding.Floor);

            EpochRedeemMetadata storage details = _epochs[epochId];
            // Using `requested` (zero in the fully-claimed state) clears stuck dust.
            details.requests[controller] = requested.saturatingSub(batchShares);
            details.totalShares -= batchShares; // batchShares <= details.totalShares (invariant: requests[c] <= totalShares)
            details.totalAssets -= batchAssets; // batchAssets = floor(batchShares * A/S) <= details.totalAssets (since batchShares <= totalShares)
            shares -= batchShares; // batchShares <= shares (via .min)
            assets += batchAssets;
        }

        return assets;
    }

    /**
     * @dev Maximum number of epoch entries in a controller's queue. Defaults to 32.
     * Prevents unbounded iteration in {_asyncMaxWithdraw} and {_asyncMaxRedeem}.
     */
    function _requestQueueLimit() internal view virtual returns (uint256) {
        return 32;
    }
}
