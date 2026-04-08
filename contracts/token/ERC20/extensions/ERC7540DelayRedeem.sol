// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {ERC7540} from "./ERC7540.sol";

abstract contract ERC7540DelayRedeem is ERC7540 {
    using SafeCast for uint256;
    using Checkpoints for Checkpoints.Trace208;

    mapping(address controller => Checkpoints.Trace208) private _redeems;
    mapping(address controller => uint256) private _claimedRedeems;

    function clock() internal view virtual returns (uint48) {
        return uint48(block.timestamp);
    }

    function delay(address /*controller*/) internal view virtual returns (uint48) {
        return 1 hours;
    }

    function _isDepositAsync() internal pure virtual override returns (bool) {
        return true;
    }

    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) internal virtual override returns (uint256) {
        // perform super call and ignore requestId
        super._requestRedeem(shares, controller, owner);

        uint48 timepoint = clock() + delay(controller);
        uint256 latest = _redeems[controller].latest();
        _redeems[controller].push(timepoint, (shares + latest).toUint208());

        return timepoint;
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        _claimedRedeems[owner] += shares;
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _pendingRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        uint48 timepoint = requestId.toUint48();
        return
            requestId > clock()
                ? _redeems[controller].upperLookup(timepoint) - _redeems[controller].upperLookup(timepoint - 1)
                : 0;
    }

    function _claimableRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        uint48 timepoint = requestId.toUint48();
        return
            requestId > clock()
                ? 0
                : Math.saturatingSub(
                    _redeems[controller].upperLookup(timepoint),
                    Math.max(_redeems[controller].upperLookup(timepoint - 1), _claimedRedeems[controller])
                );
    }

    function _asyncMaxWithdraw(address owner) internal view virtual override returns (uint256) {
        return _redeems[owner].latest() - _claimedRedeems[owner];
    }

    function _asyncMaxRedeem(address owner) internal view virtual override returns (uint256) {
        return _redeems[owner].latest() - _claimedRedeems[owner];
    }
}
