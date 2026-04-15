// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7540} from "../../token/ERC20/extensions/ERC7540.sol";
import {ERC7540DelayDeposit} from "../../token/ERC20/extensions/ERC7540DelayDeposit.sol";
import {ERC7540DelayRedeem} from "../../token/ERC20/extensions/ERC7540DelayRedeem.sol";

abstract contract ERC7540DelayMock is ERC7540DelayDeposit, ERC7540DelayRedeem {
    function clock() public view virtual override(ERC7540DelayDeposit, ERC7540DelayRedeem) returns (uint48) {
        return super.clock();
    }

    function _isDepositAsync() internal pure virtual override(ERC7540, ERC7540DelayDeposit) returns (bool) {
        return super._isDepositAsync();
    }

    function _isRedeemAsync() internal pure virtual override(ERC7540, ERC7540DelayRedeem) returns (bool) {
        return super._isRedeemAsync();
    }

    function _requestDeposit(
        uint256 assets,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540DelayDeposit) returns (uint256) {
        return super._requestDeposit(assets, controller, owner, requestId);
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override(ERC7540, ERC7540DelayDeposit) {
        super._deposit(caller, receiver, assets, shares);
    }

    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540DelayRedeem) returns (uint256) {
        return super._requestRedeem(shares, controller, owner, requestId);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override(ERC7540, ERC7540DelayRedeem) {
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _pendingDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540DelayDeposit) returns (uint256) {
        return super._pendingDepositRequest(requestId, controller);
    }

    function _claimableDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540DelayDeposit) returns (uint256) {
        return super._claimableDepositRequest(requestId, controller);
    }

    function _pendingRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540DelayRedeem) returns (uint256) {
        return super._pendingRedeemRequest(requestId, controller);
    }

    function _claimableRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540DelayRedeem) returns (uint256) {
        return super._claimableRedeemRequest(requestId, controller);
    }

    function _asyncMaxDeposit(
        address owner
    ) internal view virtual override(ERC7540, ERC7540DelayDeposit) returns (uint256) {
        return super._asyncMaxDeposit(owner);
    }

    function _asyncMaxMint(
        address owner
    ) internal view virtual override(ERC7540, ERC7540DelayDeposit) returns (uint256) {
        return super._asyncMaxMint(owner);
    }

    function _asyncMaxWithdraw(
        address owner
    ) internal view virtual override(ERC7540, ERC7540DelayRedeem) returns (uint256) {
        return super._asyncMaxWithdraw(owner);
    }

    function _asyncMaxRedeem(
        address owner
    ) internal view virtual override(ERC7540, ERC7540DelayRedeem) returns (uint256) {
        return super._asyncMaxRedeem(owner);
    }
}
