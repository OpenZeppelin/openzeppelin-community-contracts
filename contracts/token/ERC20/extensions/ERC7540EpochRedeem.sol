// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {ERC7540} from "./ERC7540.sol";

abstract contract ERC7540EpochRedeem is ERC7540 {
    using Math for uint256;
    using SafeCast for uint256;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    struct EpochRedeemMetadata {
        uint256 totalShares;
        uint256 totalAssets;
        mapping(address account => uint256) requests;
    }

    mapping(uint256 epochId => EpochRedeemMetadata) private _epochs;
    mapping(address account => DoubleEndedQueue.Bytes32Deque) private _memberOf;

    function _isRedeemAsync() internal pure virtual override returns (bool) {
        return true;
    }

    /// @dev Returns the current epoch.
    function currentRedeemEpoch() public view virtual returns (uint256) {
        return block.timestamp / 1 weeks;
    }

    function _pendingRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        EpochRedeemMetadata storage details = _epochs[requestId];
        return details.totalAssets == 0 ? details.requests[controller] : 0;
    }

    function _claimableRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        EpochRedeemMetadata storage details = _epochs[requestId];
        return details.totalAssets == 0 ? 0 : details.requests[controller];
    }

    function _asyncMaxWithdraw(address owner) internal view virtual override returns (uint256 assets) {
        uint256 result = 0;
        for (uint256 i = 0; i < _memberOf[owner].length(); ++i) {
            uint256 epochId = uint256(_memberOf[owner].at(i));
            result += Math.mulDiv(
                _claimableRedeemRequest(epochId, owner),
                _epochs[epochId].totalAssets,
                _epochs[epochId].totalShares,
                Math.Rounding.Floor
            );
        }
        return result;
    }

    function _asyncMaxRedeem(address owner) internal view virtual override returns (uint256 shares) {
        uint256 result = 0;
        for (uint256 i = 0; i < _memberOf[owner].length(); ++i) {
            uint256 epochId = uint256(_memberOf[owner].at(i));
            result += _claimableRedeemRequest(epochId, owner);
        }
        return result;
    }

    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner,
        uint256 /* requestId */ // discarded and replaced by timepoint based ids
    ) internal virtual override returns (uint256) {
        uint256 epochId = currentRedeemEpoch();
        _epochs[epochId].totalShares += shares;
        _epochs[epochId].requests[controller] += shares;

        (bool success, bytes32 lastEpochId) = _memberOf[controller].tryBack();
        if (!success || lastEpochId != bytes32(epochId)) {
            _memberOf[controller].pushBack(bytes32(epochId));

            // Limit the number of pending epochs per account to 32 to avoid O(n) loop in _asyncMaxWithdraw and _asyncMaxRedeem being a concern.
            // User that have reached the limit should execute pending (fulfilled) request to cleanup the queue.
            require(_memberOf[controller].length() < _requestQueueLimit());
        }

        return super._requestRedeem(shares, controller, owner, epochId);
    }

    function _sharesToFulfillRedeem(uint256 epochId) internal view virtual returns (uint256) {
        return epochId < currentRedeemEpoch() && _epochs[epochId].totalAssets == 0 ? _epochs[epochId].totalShares : 0;
    }

    /// Note: when epoch transition is manual, caller should bump the epoch before calling _fulfill
    function _fulfillRedeem(uint256 epochId, uint256 totalAssets) internal virtual {
        require(epochId < currentRedeemEpoch()); // TODO: too early

        EpochRedeemMetadata storage details = _epochs[epochId];
        require(details.totalShares > 0 && details.totalAssets == 0); // TODO: invalid resolve

        details.totalAssets = totalAssets;
        // TODO: emit event
    }

    function _computeAsyncWithdraw(uint256 assets, address controller) internal virtual override returns (uint256) {
        uint256 shares = 0;

        while (assets > 0) {
            uint256 epochId = uint256(_memberOf[controller].front());

            EpochRedeemMetadata storage details = _epochs[epochId];

            uint256 requested = details.requests[controller].mulDiv(
                details.totalAssets,
                details.totalShares,
                Math.Rounding.Ceil
            );
            if (requested <= assets) _memberOf[controller].popFront();

            uint256 batchAssets = requested.min(assets);
            details.totalAssets -= batchAssets; // May need saturatingSub for rounding handling
            assets -= batchAssets; // May need saturatingSub for rounding handling

            uint256 batchShares = batchAssets.mulDiv(details.totalShares, details.totalAssets, Math.Rounding.Floor);
            details.requests[controller] -= batchShares; // May need saturatingSub for rounding handling
            details.totalShares -= batchShares; // May need saturatingSub for rounding handling
            shares += batchShares;
        }

        return shares;
    }

    function _computeAsyncRedeem(uint256 shares, address controller) internal virtual override returns (uint256) {
        uint256 assets = 0;

        while (shares > 0) {
            uint256 epochId = uint256(_memberOf[controller].front());

            EpochRedeemMetadata storage details = _epochs[epochId];

            uint256 requested = details.requests[controller];
            if (requested <= shares) _memberOf[controller].popFront();

            uint256 batchShares = requested.min(shares);
            details.requests[controller] -= batchShares; // May need saturatingSub for rounding handling
            details.totalShares -= batchShares; // May need saturatingSub for rounding handling
            shares -= batchShares; // May need saturatingSub for rounding handling

            uint256 batchAssets = batchShares.mulDiv(details.totalAssets, details.totalShares, Math.Rounding.Floor);
            details.totalAssets -= batchAssets; // May need saturatingSub for rounding handling
            assets += batchAssets;
        }

        return assets;
    }

    function _requestQueueLimit() internal view virtual returns (uint256) {
        return 32;
    }
}
