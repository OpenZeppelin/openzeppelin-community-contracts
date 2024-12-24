// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Extension of {ERC20} that allows to implement a blocklist
 * mechanism that can be managed by an authorized account with the
 * {_blockUser} and {_unblockUser} functions.
 *
 * The blocklist provides the guarantee to the contract owner
 * (e.g. a DAO or a well-configured multisig) that any account won't be
 * able to execute transfers or approvals to other entities to operate
 * on its behalf if {_blockUser} was not called with such account as an
 * argument. Similarly, the account will be unblocked again if
 * {_unblockUser} is called.
 */
abstract contract ERC20Blocklist is ERC20 {
    /**
     * @dev Blocked status of addresses. True if blocked, False otherwise.
     */
    mapping(address user => bool) private _blocked;

    /**
     * @dev Emitted when a user is blocked.
     */
    event UserBlocked(address indexed user);

    /**
     * @dev Emitted when a user is unblocked.
     */
    event UserUnblocked(address indexed user);

    /**
     * @dev The operation failed because the user is blocked.
     */
    error ERC20Blocked(address user);

    /**
     * @dev Returns the blocked status of an account.
     */
    function blocked(address account) public virtual returns (bool) {
        return _blocked[account];
    }

    /**
     * @dev Blocks a user from receiving and transferring tokens, including minting and burning.
     */
    function _blockUser(address user) internal virtual returns (bool) {
        bool isBlocked = blocked(user);
        if (!isBlocked) {
            _blocked[user] = true;
            emit UserBlocked(user);
        }
        return isBlocked;
    }

    /**
     * @dev Unblocks a user from receiving and transferring tokens, including minting and burning.
     */
    function _unblockUser(address user) internal virtual returns (bool) {
        bool isBlocked = blocked(user);
        if (isBlocked) {
            _blocked[user] = false;
            emit UserUnblocked(user);
        }
        return isBlocked;
    }

    /**
     * @dev See {ERC20-_update}.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (blocked(from)) revert ERC20Blocked(from);
        if (blocked(to)) revert ERC20Blocked(to);
        super._update(from, to, value);
    }

    /**
     * @dev See {ERC20-_approve}.
     */
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual override {
        if (blocked(owner)) revert ERC20Blocked(owner);
        super._approve(owner, spender, value, emitEvent);
    }
}
