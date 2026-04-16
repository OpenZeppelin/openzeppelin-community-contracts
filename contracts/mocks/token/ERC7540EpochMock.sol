// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7540} from "../../token/ERC20/extensions/ERC7540.sol";
import {ERC7540EpochDeposit} from "../../token/ERC20/extensions/ERC7540EpochDeposit.sol";
import {ERC7540EpochRedeem} from "../../token/ERC20/extensions/ERC7540EpochRedeem.sol";

abstract contract ERC7540EpochMock is ERC7540EpochDeposit, ERC7540EpochRedeem {
    function _isDepositAsync() internal pure virtual override(ERC7540, ERC7540EpochDeposit) returns (bool) {
        return super._isDepositAsync();
    }

    function _isRedeemAsync() internal pure virtual override(ERC7540, ERC7540EpochRedeem) returns (bool) {
        return super._isRedeemAsync();
    }

    function _consumeAsyncDeposit(
        uint256 assets,
        address controller
    ) internal virtual override(ERC7540, ERC7540EpochDeposit) returns (uint256) {
        return super._consumeAsyncDeposit(assets, controller);
    }

    function _consumeAsyncMint(
        uint256 shares,
        address controller
    ) internal virtual override(ERC7540, ERC7540EpochDeposit) returns (uint256) {
        return super._consumeAsyncMint(shares, controller);
    }

    function _consumeAsyncRedeem(
        uint256 shares,
        address controller
    ) internal virtual override(ERC7540, ERC7540EpochRedeem) returns (uint256) {
        return super._consumeAsyncRedeem(shares, controller);
    }

    function _consumeAsyncWithdraw(
        uint256 assets,
        address controller
    ) internal virtual override(ERC7540, ERC7540EpochRedeem) returns (uint256) {
        return super._consumeAsyncWithdraw(assets, controller);
    }

    function _requestDeposit(
        uint256 assets,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540EpochDeposit) returns (uint256) {
        return super._requestDeposit(assets, controller, owner, requestId);
    }

    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540EpochRedeem) returns (uint256) {
        return super._requestRedeem(shares, controller, owner, requestId);
    }

    function _pendingDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540EpochDeposit) returns (uint256) {
        return super._pendingDepositRequest(requestId, controller);
    }

    function _claimableDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540EpochDeposit) returns (uint256) {
        return super._claimableDepositRequest(requestId, controller);
    }

    function _pendingRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540EpochRedeem) returns (uint256) {
        return super._pendingRedeemRequest(requestId, controller);
    }

    function _claimableRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540EpochRedeem) returns (uint256) {
        return super._claimableRedeemRequest(requestId, controller);
    }

    function _asyncMaxDeposit(
        address owner
    ) internal view virtual override(ERC7540, ERC7540EpochDeposit) returns (uint256) {
        return super._asyncMaxDeposit(owner);
    }

    function _asyncMaxMint(
        address owner
    ) internal view virtual override(ERC7540, ERC7540EpochDeposit) returns (uint256) {
        return super._asyncMaxMint(owner);
    }

    function _asyncMaxWithdraw(
        address owner
    ) internal view virtual override(ERC7540, ERC7540EpochRedeem) returns (uint256) {
        return super._asyncMaxWithdraw(owner);
    }

    function _asyncMaxRedeem(
        address owner
    ) internal view virtual override(ERC7540, ERC7540EpochRedeem) returns (uint256) {
        return super._asyncMaxRedeem(owner);
    }

    function _requestQueueLimit()
        internal
        view
        virtual
        override(ERC7540EpochDeposit, ERC7540EpochRedeem)
        returns (uint256)
    {
        return super._requestQueueLimit();
    }
}
