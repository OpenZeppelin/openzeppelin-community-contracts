// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC7540} from "./ERC7540.sol";

abstract contract ERC7540AdminFulfillRedeem is ERC7540 {
    struct PendingRedeem {
        uint256 pendingShares;
        uint256 claimableShares;
        uint256 claimableAssets;
    }
    mapping(address controller => PendingRedeem) private _redeems;

    /// @dev Emitted when a redeem request transitions from Pending to Claimable.
    event RedeemClaimable(address indexed controller, uint256 indexed requestId, uint256 assets, uint256 shares);

    /// @dev The amount of shares requested is greater than the amount of shares pending.
    error ERC7540RedeemInsufficientPendingShares(uint256 shares, uint256 pendingShares);

    function _isRedeemAsync() internal pure virtual override returns (bool) {
        return true;
    }

    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner
    ) internal virtual override returns (uint256) {
        _redeems[controller].pendingShares += shares;
        return super._requestRedeem(shares, controller, owner);
    }

    function _fulfillRedeem(uint256 shares, uint256 assets, address controller) internal virtual {
        uint256 pendingShares = pendingRedeemRequest(0, controller);
        require(shares <= pendingShares, ERC7540RedeemInsufficientPendingShares(shares, pendingShares));

        _redeems[controller].pendingShares -= shares;
        _redeems[controller].claimableShares += shares;
        _redeems[controller].claimableAssets += assets;

        emit RedeemClaimable(controller, 0, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        _redeems[receiver].claimableAssets = Math.saturatingSub(_redeems[receiver].claimableAssets, assets);
        _redeems[receiver].claimableShares = Math.saturatingSub(_redeems[receiver].claimableShares, shares);
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _pendingRedeemRequest(
        uint256 /*requestId*/,
        address controller
    ) internal view virtual override returns (uint256) {
        return _redeems[controller].pendingShares;
    }

    function _claimableRedeemRequest(
        uint256 /*requestId*/,
        address controller
    ) internal view virtual override returns (uint256) {
        return _redeems[controller].claimableShares;
    }

    function _asyncMaxWithdraw(address owner) internal view virtual override returns (uint256) {
        return _redeems[owner].claimableAssets;
    }

    function _asyncMaxRedeem(address owner) internal view virtual override returns (uint256) {
        return _redeems[owner].claimableShares;
    }
}
