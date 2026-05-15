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
 * NOTE: Claims pay each controller's pro-rata share floor-rounded against the remaining epoch
 * totals. With very small fulfillment values (e.g. an epoch settling 3 assets for 2 shares
 * across 3 equal claimants), rounding can leave one controller with up to 1 "wei" of
 * unclaimable residue. At realistic ERC-20 token decimals this is sub-unit and economically
 * immaterial. Unlike ERC-4626's inflation-attack surface, the per-epoch `totalAssets` and
 * `totalShares` cannot be inflated by donation (they only change via {requestDeposit} and
 * {_fulfillDeposit}); deployers wanting finer per-claim granularity can set {_decimalsOffset}
 * to scale share precision relative to assets.
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

    /// @dev Emitted when a deposit epoch transitions from Pending to Claimable via {_fulfillDeposit}.
    event ERC7540EpochDepositFulfilled(uint256 indexed epochId, uint256 totalAssets, uint256 totalShares);

    /// @dev Attempted to fulfill a deposit epoch that has not yet ended.
    error ERC7540EpochDepositTooEarly(uint256 epochId);

    /// @dev Attempted to fulfill a deposit epoch with no pending requests.
    error ERC7540EpochDepositEmptyEpoch(uint256 epochId);

    /// @dev Attempted to fulfill a deposit epoch that has already been fulfilled.
    error ERC7540EpochDepositAlreadyFulfilled(uint256 epochId);

    /// @inheritdoc ERC7540
    function _isDepositAsync() internal pure virtual override returns (bool) {
        return true;
    }

    /// @dev Returns the current epoch ID. Defaults to `block.timestamp / 1 weeks`.
    function currentDepositEpoch() public view virtual returns (uint256) {
        return block.timestamp / 1 weeks;
    }

    /**
     * @dev Returns the total assets queued in `epochId`. Equals the sum of all deposit requests
     * during the Pending phase; decreases as claimants consume their pro-rata share once the
     * epoch is fulfilled, and reaches 0 once the epoch is fully claimed.
     */
    function totalDepositAssets(uint256 epochId) public view virtual returns (uint256) {
        return _epochs[epochId].totalAssets;
    }

    /**
     * @dev Returns the shares allocated to `epochId` at fulfillment. Zero before
     * {_fulfillDeposit} is called; decreases as claimants consume their pro-rata share.
     * Together with {totalDepositAssets} it encodes the locked epoch rate.
     */
    function totalDepositShares(uint256 epochId) public view virtual returns (uint256) {
        return _epochs[epochId].totalShares;
    }

    /**
     * @dev A request is pending if its epoch has not yet been fulfilled (`totalShares == 0`) and
     * still has assets queued (`totalAssets > 0`).
     */
    function _pendingDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        return totalDepositShares(requestId) == 0 ? _pendingAvailableDepositRequest(requestId, controller) : 0;
    }

    /**
     * @dev Returns the controller's stored deposit request for `requestId`, or 0 if the epoch
     * has been fully claimed (`totalAssets == 0`).
     */
    function _pendingAvailableDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual returns (uint256) {
        return totalDepositAssets(requestId) == 0 ? 0 : _epochs[requestId].requests[controller];
    }

    /// @dev A request is claimable if its epoch has been fulfilled (`totalShares > 0`).
    function _claimableDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        return totalDepositShares(requestId) == 0 ? 0 : _epochs[requestId].requests[controller];
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
            result += _convertToDepositShares(epochId, _claimableDepositRequest(epochId, owner), Math.Rounding.Floor);
        }
        return result;
    }

    /// @dev Converts `assets` to shares at `epochId`'s locked rate. Returns 0 if `totalAssets` is 0.
    function _convertToDepositShares(
        uint256 epochId,
        uint256 assets,
        Math.Rounding rounding
    ) internal view virtual returns (uint256) {
        // An epoch's `totalAssets` may be 0 while some `requests[*]` slots are non-zero,
        // when other controllers' share-driven claims ({_consumeClaimableMint}) round
        // `requested` up via ceil and the saturating decrement zeroes the shared pool
        // before all per-controller residues are allocated.
        uint256 totalAssets = totalDepositAssets(epochId);
        return totalAssets == 0 ? 0 : assets.mulDiv(totalDepositShares(epochId), totalAssets, rounding);
    }

    /// @dev Converts `shares` to assets at `epochId`'s locked rate. Returns 0 if `totalShares` is 0.
    function _convertToDepositAssets(
        uint256 epochId,
        uint256 shares,
        Math.Rounding rounding
    ) internal view virtual returns (uint256) {
        // An epoch's `totalShares` may be 0 while some `requests[*]` slots are non-zero,
        // when other controllers' share-driven claims ({_consumeClaimableMint}) round
        // `requested` up via ceil and the saturating decrement zeroes the shared pool
        // before all per-controller residues are allocated.
        uint256 totalShares = totalDepositShares(epochId);
        return totalShares == 0 ? 0 : shares.mulDiv(totalDepositAssets(epochId), totalShares, rounding);
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
        require(epochId < currentDepositEpoch(), ERC7540EpochDepositTooEarly(epochId));

        uint256 totalAssets = totalDepositAssets(epochId);
        require(totalAssets > 0, ERC7540EpochDepositEmptyEpoch(epochId));
        require(totalDepositShares(epochId) == 0, ERC7540EpochDepositAlreadyFulfilled(epochId));

        _epochs[epochId].totalShares = totalShares;
        emit ERC7540EpochDepositFulfilled(epochId, totalAssets, totalShares);
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

            uint256 requested = _pendingAvailableDepositRequest(epochId, controller);
            if (requested <= assets) _memberOf[controller].popFront();

            uint256 batchAssets = requested.min(assets);
            uint256 batchShares = _convertToDepositShares(epochId, batchAssets, Math.Rounding.Floor);

            EpochDepositMetadata storage details = _epochs[epochId];
            // Using `requested` (zero in the fully-claimed state) clears stuck dust.
            details.requests[controller] = requested.saturatingSub(batchAssets);
            details.totalAssets -= batchAssets; // batchAssets <= details.totalAssets (invariant: requests[c] <= totalAssets)
            details.totalShares -= batchShares; // batchShares = floor(batchAssets * S/A) <= details.totalShares (since batchAssets <= totalAssets)
            assets -= batchAssets; // batchAssets <= assets (via .min)
            shares += batchShares;
        }

        return shares;
    }

    /// @dev Same as {_consumeClaimableDeposit} but iterates by shares instead of assets.
    function _consumeClaimableMint(uint256 shares, address controller) internal virtual override returns (uint256) {
        uint256 assets = 0;

        while (shares > 0) {
            uint256 epochId = uint256(_memberOf[controller].front());

            uint256 requestedAssets = _pendingAvailableDepositRequest(epochId, controller);
            uint256 requested = _convertToDepositShares(epochId, requestedAssets, Math.Rounding.Ceil);
            if (requested <= shares) _memberOf[controller].popFront();

            uint256 batchShares = requested.min(shares);
            uint256 batchAssets = _convertToDepositAssets(epochId, batchShares, Math.Rounding.Floor);

            EpochDepositMetadata storage details = _epochs[epochId];
            // Using `requestedAssets` (zero in the fully-claimed state) clears stuck dust
            // The saturation absorbs the 1-wei ceil/floor excess in `batchAssets` when fully
            // claimed, so `totalAssets` reduces to 0 cleanly and the {_fulfillDeposit} sentinel
            // stays unambiguous.
            details.requests[controller] = requestedAssets.saturatingSub(batchAssets);
            details.totalAssets = details.totalAssets.saturatingSub(batchAssets);
            details.totalShares = details.totalShares.saturatingSub(batchShares);
            shares -= batchShares; // batchShares <= shares (via .min)
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
