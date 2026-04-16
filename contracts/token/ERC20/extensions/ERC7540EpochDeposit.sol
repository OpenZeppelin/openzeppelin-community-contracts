// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {ERC7540} from "./ERC7540.sol";

abstract contract ERC7540EpochDeposit is ERC7540 {
    using Math for uint256;
    using SafeCast for uint256;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    struct EpochDepositMetadata {
        uint256 totalAssets;
        uint256 totalShares;
        mapping(address account => uint256) requests;
    }

    mapping(uint256 epochId => EpochDepositMetadata) private _epochs;
    mapping(address account => DoubleEndedQueue.Bytes32Deque) private _memberOf;

    function _isDepositAsync() internal pure virtual override returns (bool) {
        return true;
    }

    /// @dev Returns the current epoch.
    function currentDepositEpoch() public view virtual returns (uint256) {
        return block.timestamp / 1 weeks;
    }

    function _pendingDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        EpochDepositMetadata storage details = _epochs[requestId];
        return details.totalShares == 0 ? details.requests[controller] : 0;
    }

    function _claimableDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        EpochDepositMetadata storage details = _epochs[requestId];
        return details.totalShares == 0 ? 0 : details.requests[controller];
    }

    function _asyncMaxDeposit(address owner) internal view virtual override returns (uint256 assets) {
        uint256 result = 0;
        for (uint256 i = 0; i < _memberOf[owner].length(); ++i) {
            uint256 epochId = uint256(_memberOf[owner].at(i));
            result += _claimableDepositRequest(epochId, owner);
        }
        return result;
    }

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

    function _requestDeposit(
        uint256 assets,
        address controller,
        address owner,
        uint256 /* requestId */ // discarded and replaced by timepoint based ids
    ) internal virtual override returns (uint256) {
        uint256 epochId = currentDepositEpoch();
        _epochs[epochId].totalAssets += assets;
        _epochs[epochId].requests[controller] += assets;

        (bool success, bytes32 lastEpochId) = _memberOf[controller].tryBack();
        if (!success || lastEpochId != bytes32(epochId)) {
            _memberOf[controller].pushBack(bytes32(epochId));

            // Limit the number of pending epochs per account to 32 to avoid O(n) loop in _asyncMaxWithdraw and _asyncMaxRedeem being a concern.
            // User that have reached the limit should execute pending (fulfilled) request to cleanup the queue.
            require(_memberOf[controller].length() < _requestQueueLimit());
        }

        return super._requestDeposit(assets, controller, owner, epochId);
    }

    function _assetsToFullfillDeposit(uint256 epochId) internal view virtual returns (uint256) {
        return epochId < currentDepositEpoch() && _epochs[epochId].totalShares == 0 ? _epochs[epochId].totalAssets : 0;
    }

    /// Note: when epoch transition is manual, caller should bump the epoch before calling _fulfill
    function _fulfillDeposit(uint256 epochId, uint256 totalShares) internal virtual {
        require(epochId < currentDepositEpoch()); // TODO: too early

        EpochDepositMetadata storage details = _epochs[epochId];
        require(details.totalAssets > 0 && details.totalShares == 0); // TODO: invalid resolve

        details.totalShares = totalShares;
        // TODO: emit event
    }

    function _computeAsyncDeposit(uint256 assets, address controller) internal virtual override returns (uint256) {
        uint256 shares = 0;

        while (assets > 0) {
            uint256 epochId = uint256(_memberOf[controller].front());

            EpochDepositMetadata storage details = _epochs[epochId];

            uint256 requested = details.requests[controller];
            if (requested <= assets) _memberOf[controller].popFront();

            uint256 batchAssets = requested.min(assets);
            details.requests[controller] -= batchAssets; // May need saturatingSub for rounding handling
            details.totalAssets -= batchAssets; // May need saturatingSub for rounding handling
            assets -= batchAssets; // May need saturatingSub for rounding handling

            uint256 batchShares = batchAssets.mulDiv(details.totalShares, details.totalAssets, Math.Rounding.Floor);
            details.totalShares -= batchShares; // May need saturatingSub for rounding handling
            shares += batchShares;
        }

        return shares;
    }

    function _computeAsyncMint(uint256 shares, address controller) internal virtual override returns (uint256) {
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
            details.totalShares -= batchShares; // May need saturatingSub for rounding handling
            shares -= batchShares; // May need saturatingSub for rounding handling

            uint256 batchAssets = batchShares.mulDiv(details.totalAssets, details.totalShares, Math.Rounding.Floor);
            details.requests[controller] -= batchAssets; // May need saturatingSub for rounding handling
            details.totalAssets -= batchAssets; // May need saturatingSub for rounding handling
            assets += batchAssets;
        }

        return assets;
    }

    function _requestQueueLimit() internal view virtual returns (uint256) {
        return 32;
    }
}
