// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7540} from "../../token/ERC20/extensions/ERC7540.sol";
import {ERC7540AdminFulfillDeposit} from "../../token/ERC20/extensions/ERC7540AdminFulfillDeposit.sol";
import {ERC7540AdminFulfillRedeem} from "../../token/ERC20/extensions/ERC7540AdminFulfillRedeem.sol";

abstract contract ERC7540AdminFulfillMock is ERC7540AdminFulfillDeposit, ERC7540AdminFulfillRedeem {
    function _isDepositAsync() internal pure virtual override(ERC7540, ERC7540AdminFulfillDeposit) returns (bool) {
        return super._isDepositAsync();
    }

    function _isRedeemAsync() internal pure virtual override(ERC7540, ERC7540AdminFulfillRedeem) returns (bool) {
        return super._isRedeemAsync();
    }

    function _requestDeposit(
        uint256 assets,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540AdminFulfillDeposit) returns (uint256) {
        return super._requestDeposit(assets, controller, owner, requestId);
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal virtual override(ERC7540, ERC7540AdminFulfillDeposit) {
        super._deposit(caller, receiver, assets, shares);
    }

    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540AdminFulfillRedeem) returns (uint256) {
        return super._requestRedeem(shares, controller, owner, requestId);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override(ERC7540, ERC7540AdminFulfillRedeem) {
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _pendingDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540AdminFulfillDeposit) returns (uint256) {
        return super._pendingDepositRequest(requestId, controller);
    }

    function _claimableDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540AdminFulfillDeposit) returns (uint256) {
        return super._claimableDepositRequest(requestId, controller);
    }

    function _pendingRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540AdminFulfillRedeem) returns (uint256) {
        return super._pendingRedeemRequest(requestId, controller);
    }

    function _claimableRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540AdminFulfillRedeem) returns (uint256) {
        return super._claimableRedeemRequest(requestId, controller);
    }

    function _asyncMaxDeposit(
        address owner
    ) internal view virtual override(ERC7540, ERC7540AdminFulfillDeposit) returns (uint256) {
        return super._asyncMaxDeposit(owner);
    }

    function _asyncMaxMint(
        address owner
    ) internal view virtual override(ERC7540, ERC7540AdminFulfillDeposit) returns (uint256) {
        return super._asyncMaxMint(owner);
    }

    function _asyncMaxWithdraw(
        address owner
    ) internal view virtual override(ERC7540, ERC7540AdminFulfillRedeem) returns (uint256) {
        return super._asyncMaxWithdraw(owner);
    }

    function _asyncMaxRedeem(
        address owner
    ) internal view virtual override(ERC7540, ERC7540AdminFulfillRedeem) returns (uint256) {
        return super._asyncMaxRedeem(owner);
    }
}
