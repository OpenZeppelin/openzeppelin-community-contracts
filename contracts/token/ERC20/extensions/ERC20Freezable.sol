// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC7943Fungible} from "../../../interfaces/IERC7943.sol";

/**
 * @dev Extension of {ERC20} that allows to implement a freezing
 * mechanism that can be managed by an authorized account with the
 * {_freezeTokens} and {_unfreezeTokens} functions.
 *
 * The freezing mechanism provides the guarantee to the contract owner
 * (e.g. a DAO or a well-configured multisig) that a specific amount
 * of tokens held by an account won't be transferable until those
 * tokens are unfrozen using {_unfreezeTokens}.
 */
abstract contract ERC20Freezable is ERC20 {
    /// @dev Frozen amount of tokens per address.
    mapping(address account => uint256) private _frozenBalances;

    /// @dev The operation failed because the user has insufficient unfrozen balance.
    error ERC20InsufficientUnfrozenBalance(address user, uint256 needed, uint256 available);

    /// @dev Returns the frozen balance of an account.
    function frozen(address account) public view virtual returns (uint256) {
        return _frozenBalances[account];
    }

    /// @dev Returns the available (unfrozen) balance of an account. Up to {balanceOf}.
    function available(address account) public view virtual returns (uint256) {
        (bool success, uint256 unfrozen) = Math.trySub(balanceOf(account), _frozenBalances[account]);
        return success ? unfrozen : 0;
    }

    /// @dev Internal function to set the frozen token amount for a user.
    function _setFrozen(address user, uint256 amount) internal virtual {
        _frozenBalances[user] = amount;
        emit IERC7943Fungible.Frozen(user, amount);
    }

    /**
     * @dev See {ERC20-_update}.
     *
     * Requirements:
     *
     * * `from` must have sufficient unfrozen balance.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0)) {
            uint256 unfrozen = available(from);
            require(unfrozen >= value, ERC20InsufficientUnfrozenBalance(from, value, unfrozen));
        }
        super._update(from, to, value);
    }

    // We don't check frozen balance for approvals since the actual transfer
    // will be checked in _update. This allows for more flexible approval patterns.
}
