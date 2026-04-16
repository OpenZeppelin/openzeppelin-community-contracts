// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7540} from "../../token/ERC20/extensions/ERC7540.sol";
import {ERC7540AdminDeposit} from "../../token/ERC20/extensions/ERC7540AdminDeposit.sol";
import {ERC7540AdminRedeem} from "../../token/ERC20/extensions/ERC7540AdminRedeem.sol";

abstract contract ERC7540AdminMock is ERC7540AdminDeposit, ERC7540AdminRedeem {
    function _isDepositAsync() internal pure virtual override(ERC7540, ERC7540AdminDeposit) returns (bool) {
        return super._isDepositAsync();
    }

    function _isRedeemAsync() internal pure virtual override(ERC7540, ERC7540AdminRedeem) returns (bool) {
        return super._isRedeemAsync();
    }

    function _requestDeposit(
        uint256 assets,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540AdminDeposit) returns (uint256) {
        return super._requestDeposit(assets, controller, owner, requestId);
    }

    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540AdminRedeem) returns (uint256) {
        return super._requestRedeem(shares, controller, owner, requestId);
    }

    function _pendingDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540AdminDeposit) returns (uint256) {
        return super._pendingDepositRequest(requestId, controller);
    }

    function _pendingRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540AdminRedeem) returns (uint256) {
        return super._pendingRedeemRequest(requestId, controller);
    }

    function _claimableDepositRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540AdminDeposit) returns (uint256) {
        return super._claimableDepositRequest(requestId, controller);
    }

    function _claimableRedeemRequest(
        uint256 requestId,
        address controller
    ) internal view virtual override(ERC7540, ERC7540AdminRedeem) returns (uint256) {
        return super._claimableRedeemRequest(requestId, controller);
    }

    function _consumeClaimableDeposit(
        uint256 assets,
        address controller
    ) internal virtual override(ERC7540, ERC7540AdminDeposit) returns (uint256) {
        return super._consumeClaimableDeposit(assets, controller);
    }

    function _consumeClaimableMint(
        uint256 shares,
        address controller
    ) internal virtual override(ERC7540, ERC7540AdminDeposit) returns (uint256) {
        return super._consumeClaimableMint(shares, controller);
    }

    function _consumeClaimableRedeem(
        uint256 shares,
        address controller
    ) internal virtual override(ERC7540, ERC7540AdminRedeem) returns (uint256) {
        return super._consumeClaimableRedeem(shares, controller);
    }

    function _consumeClaimableWithdraw(
        uint256 assets,
        address controller
    ) internal virtual override(ERC7540, ERC7540AdminRedeem) returns (uint256) {
        return super._consumeClaimableWithdraw(assets, controller);
    }

    function _asyncMaxDeposit(
        address owner
    ) internal view virtual override(ERC7540, ERC7540AdminDeposit) returns (uint256) {
        return super._asyncMaxDeposit(owner);
    }

    function _asyncMaxMint(
        address owner
    ) internal view virtual override(ERC7540, ERC7540AdminDeposit) returns (uint256) {
        return super._asyncMaxMint(owner);
    }

    function _asyncMaxWithdraw(
        address owner
    ) internal view virtual override(ERC7540, ERC7540AdminRedeem) returns (uint256) {
        return super._asyncMaxWithdraw(owner);
    }

    function _asyncMaxRedeem(
        address owner
    ) internal view virtual override(ERC7540, ERC7540AdminRedeem) returns (uint256) {
        return super._asyncMaxRedeem(owner);
    }
}
