// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AbstractSplitter} from "../finance/AbstractSplitter.sol";

abstract contract PaymentSplitterMock is AbstractSplitter, ERC20 {
    IERC20 public immutable token;

    constructor(IERC20 _token) {
        token = _token;
    }

    /**
     * @dev Internal hook: shares are represented as ERC20 tokens
     */
    function _shares(address account) internal view virtual override returns (uint256) {
        return balanceOf(account);
    }

    /**
     * @dev Internal hook: get total shares
     */
    function _totalShares() internal view virtual override returns (uint256) {
        return totalSupply();
    }

    /**
     * @dev Internal hook: get splitter balance
     */
    function _balance() internal view virtual override returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @dev Internal hook: call when token are released
     */
    function _doRelease(address to, uint256 amount) internal virtual override {
        SafeERC20.safeTransfer(token, to, amount);
    }

    function _update(address from, address to, uint256 amount) internal virtual override {
        _beforeShareTransfer(from, to, amount);
        super._update(from, to, amount);
    }
}
