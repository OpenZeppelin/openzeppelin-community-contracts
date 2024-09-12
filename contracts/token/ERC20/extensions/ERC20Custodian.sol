// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Contract module which allows children to implement a custodian
 * mechanism that can be managed by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * functions `freeze` and `unfreeze`, which can be used to manage the
 * frozen balance of a user.
 */
abstract contract ERC20Custodian is ERC20 {
    /**
     * @dev The amount of tokens frozen by user address.
     */
    mapping(address => uint256) public frozen;

    /**
     * @dev Emitted when tokens are frozen for a user.
     * @param user The address of the user whose tokens were frozen.
     * @param amount The amount of tokens that were frozen.
     */
    event TokensFrozen(address indexed user, uint256 amount);

    /**
     * @dev Emitted when tokens are unfrozen for a user.
     * @param user The address of the user whose tokens were unfrozen.
     * @param amount The amount of tokens that were unfrozen.
     */
    event TokensUnfrozen(address indexed user, uint256 amount);

    /**
     * @dev The operation failed because the user has insufficient unfrozen balance.
     */
    error InsufficientUnfrozenBalance();

    /**
     * @dev The operation failed because the user has insufficient frozen balance.
     */
    error InsufficientFrozenBalance();

    // TODO: should availableBalance be the default for `balanceOf`?

    /**
     * @dev Returns the available (unfrozen) balance of an account.
     * @param account The address to query the available balance of.
     * @return The amount of tokens available for transfer.
     */
    function availableBalance(address account) public view returns (uint256) {
        return balanceOf(account) - frozen[account];
    }

    /**
     * @dev Checks if the user is authorized to perform the operation.
     * @param user The address of the user to check.
     * @return True if the user is authorized, false otherwise.
     */
    function _authorized(address user) internal view virtual returns (bool) {}

    /**
     * @dev Freezes a specified amount of tokens for a user.
     * @param user The address of the user whose tokens to freeze.
     * @param amount The amount of tokens to freeze.
     *
     * Requirements:
     *
     * - The user must have sufficient unfrozen balance.
     */
    function _freeze(address user, uint256 amount) internal virtual {
        if (availableBalance(user) < amount) revert InsufficientUnfrozenBalance();
        frozen[user] += amount;
        emit TokensFrozen(user, amount);
    }

    /**
     * @dev Unfreezes a specified amount of tokens for a user.
     * @param user The address of the user whose tokens to unfreeze.
     * @param amount The amount of tokens to unfreeze.
     *
     * Requirements:
     *
     * - The user must have sufficient frozen balance.
     */
    function _unfreeze(address user, uint256 amount) internal virtual {
        if (frozen[user] < amount) revert InsufficientFrozenBalance();
        frozen[user] -= amount;
        emit TokensUnfrozen(user, amount);
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && _authorized(msg.sender)) {
            if (availableBalance(from) < value) revert InsufficientUnfrozenBalance();
        }
        super._update(from, to, value);
    }
}
