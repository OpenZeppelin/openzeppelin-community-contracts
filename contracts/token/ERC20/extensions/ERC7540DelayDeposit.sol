// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {ERC7540} from "./ERC7540.sol";

abstract contract ERC7540DelayDeposit is ERC7540 {
    using SafeCast for uint256;
    using Checkpoints for Checkpoints.Trace208;

    mapping(address controller => Checkpoints.Trace208 trace) private _deposits;
    mapping(address controller => uint256) private _claimedDeposits;

    function clock() internal view virtual returns (uint48) {
        return uint48(block.timestamp);
    }

    function delay(address /*controller*/) internal view virtual returns (uint48) {
        return 1 hours;
    }

    function _isDepositAsync() internal pure virtual override returns (bool) {
        return true;
    }

    function _requestDeposit(
        uint256 assets,
        address controller,
        address owner
    ) internal virtual override returns (uint256) {
        // perform super call and ignore requestId
        super._requestDeposit(assets, controller, owner);

        uint48 timepoint = clock() + delay(controller);
        uint256 latest = _deposits[controller].latest();

        _deposits[controller].push(timepoint, (assets + latest).toUint208());

        return timepoint;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        _claimedDeposits[receiver] += assets;
        super._deposit(caller, receiver, assets, shares);
    }

    function _pendingDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        uint48 timepoint = requestId.toUint48();
        return
            requestId > clock()
                ? _deposits[controller].upperLookup(timepoint) - _deposits[controller].upperLookup(timepoint - 1)
                : 0;
    }

    function _claimableDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override returns (uint256) {
        uint48 timepoint = requestId.toUint48();
        return
            requestId > clock()
                ? 0
                : Math.saturatingSub(
                    _deposits[controller].upperLookup(timepoint),
                    Math.max(_deposits[controller].upperLookup(timepoint - 1), _claimedDeposits[controller])
                );
    }

    function _asyncMaxDeposit(address owner) internal view virtual override returns (uint256) {
        return _deposits[owner].latest() - _claimedDeposits[owner];
    }

    function _asyncMaxMint(address owner) internal view virtual override returns (uint256) {
        return _convertToShares(_deposits[owner].latest() - _claimedDeposits[owner], Math.Rounding.Floor);
    }
}
