// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC7540} from "./ERC7540.sol";

abstract contract ERC7540AdminFulfillDeposit is ERC7540 {
    struct PendingDeposit {
        uint256 pendingAssets;
        uint256 claimableAssets;
        uint256 claimableShares;
    }

    mapping(address controller => PendingDeposit) private _deposits;

    /// @dev Emitted when a deposit request transitions from Pending to Claimable.
    event DepositClaimable(address indexed controller, uint256 indexed requestId, uint256 assets, uint256 shares);

    /// @dev The amount of assets requested is greater than the amount of assets pending.
    error ERC7540DepositInsufficientPendingAssets(uint256 assets, uint256 pendingAssets);

    function _isDepositAsync() internal pure virtual override returns (bool) {
        return true;
    }

    function _requestDeposit(
        uint256 assets,
        address controller,
        address owner
    ) internal virtual override returns (uint256) {
        _deposits[controller].pendingAssets += assets;
        return super._requestDeposit(assets, controller, owner);
    }

    function _fulfillDeposit(uint256 assets, uint256 shares, address controller) internal virtual {
        uint256 pendingAssets = pendingDepositRequest(0, controller);
        require(assets <= pendingAssets, ERC7540DepositInsufficientPendingAssets(assets, pendingAssets));

        _deposits[controller].pendingAssets -= assets;
        _deposits[controller].claimableAssets += assets;
        _deposits[controller].claimableShares += shares;

        emit DepositClaimable(controller, 0, assets, shares);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual override {
        _deposits[receiver].claimableAssets = Math.saturatingSub(_deposits[receiver].claimableAssets, assets);
        _deposits[receiver].claimableShares = Math.saturatingSub(_deposits[receiver].claimableShares, shares);
        super._deposit(caller, receiver, assets, shares);
    }

    function _pendingDepositRequest(
        uint256 /*requestId*/,
        address controller
    ) internal view virtual override returns (uint256) {
        return _deposits[controller].pendingAssets;
    }

    function _claimableDepositRequest(
        uint256 /*requestId*/,
        address controller
    ) internal view virtual override returns (uint256) {
        return _deposits[controller].claimableAssets;
    }

    function _asyncMaxDeposit(address owner) internal view virtual override returns (uint256) {
        return _deposits[owner].claimableAssets;
    }

    function _asyncMaxMint(address owner) internal view virtual override returns (uint256) {
        return _deposits[owner].claimableShares;
    }
}
