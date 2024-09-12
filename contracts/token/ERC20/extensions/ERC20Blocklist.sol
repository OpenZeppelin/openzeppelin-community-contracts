// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Contract module which allows children to implement a blocklist
 * mechanism that can be managed by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * functions `_blockUser` and `_unblockUser`, which can be used to
 * manage the blocklist in your contract.
 */
abstract contract ERC20Blocklist is ERC20 {
    // Blocked status of addresses. True if blocked, False otherwise.
    mapping(address => bool) public blocked;

    /**
     * @dev Emitted when a user is blocked.
     * @param user The address of the user that was blocked.
     */
    event UserBlocked(address indexed user);

    /**
     * @dev Emitted when a user is unblocked.
     * @param user The address of the user that was unblocked.
     */
    event UserUnblocked(address indexed user);

    /**
     * @dev The operation failed because the user is blocked.
     */
    error UserIsBlocked();

    /**
     * @dev The operation failed because the user is not blocked.
     */
    error UserIsNotBlocked();

    /**
     * @dev Blocks a user.
     * @param user The address of the user to block.
     *
     * Requirements:
     *
     * - The user must not be blocked.
     */
    function _blockUser(address user) internal virtual {
        if (blocked[user]) revert UserIsBlocked();
        blocked[user] = true;
        emit UserBlocked(user);
    }

    /**
     * @dev Unblocks a user.
     * @param user The address of the user to unblock.
     *
     * Requirements:
     *
     * - The user must be blocked.
     */
    function _unblockUser(address user) internal virtual {
        if (!blocked[user]) revert UserIsNotBlocked();
        blocked[user] = false;
        emit UserUnblocked(user);
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (blocked[from] || blocked[to]) revert UserIsBlocked();
        super._update(from, to, value);
    }

    function approve(address spender, uint256 value) public virtual override returns (bool) {
        if (blocked[msg.sender]) revert UserIsBlocked();
        return super.approve(spender, value);
    }
}
