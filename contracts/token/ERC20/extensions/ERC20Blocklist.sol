// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Extension of {ERC20} that allows to implement a blocklist
 * mechanism that can be managed by an authorized account through {blockUser} and {unblockUser}
 *
 * This implementation allows operation to every account by default except for those that were
 * blocked by the contract owner (e.g. a DAO or a well-configured multisig). Accounts won't
 * be able to execute transfers or approvals to other entities to operation on their behalf after
 * {_blockUser} is called. Similarly, the account can operate again after calling {_unblockUser}.
 *
 */
abstract contract ERC20Blocklist is ERC20 {
    /**
     * @dev Blocked status of addresses. True if blocked, False otherwise.
     */
    mapping(address => bool) public blocked;

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
     * @dev The operation failed because the user is not blocked.
     */

    /**
     * @dev Blocks a user.
     *
     */
    function _blockUser(address user) internal virtual {
        if (!blocked[user]) {
            blocked[user] = true;
            emit UserBlocked(user);
        }
    }

    /**
     * @dev Unblocks a user.
     *
     * Requirements:
     *
     * - The user must be blocked.
     */
    function _unblockUser(address user) internal virtual {
        if (blocked[user]) {
            blocked[user] = false;
            emit UserUnblocked(user);
        }
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (blocked[from]) revert ERC20Blocked(from);
        if (blocked[to]) revert ERC20Blocked(to);
        super._update(from, to, value);
    }

    function approve(address spender, uint256 value) public virtual override returns (bool) {
        address owner = _msgSender();
        if (blocked[owner]) revert UserIsBlocked(owner);
        _approve(owner, spender, value);
        return true;
    }
}
