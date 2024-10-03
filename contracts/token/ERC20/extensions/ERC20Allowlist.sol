// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Extension of {ERC20} that allows to implement an allowlist
 * mechanism that can be managed by an authorized account with the {disallowUser} and {allowUser} functions.
 * The allowlist provides the guarantee to the contract owner (e.g. a DAO or a well-configured multisig)
 * that any account won't be able to execute transfers or approvals to other entities to operate on
 * its behalf if {_allowUser} was not called with such account as an argument. Similarly, the account
 * will be blocked again if {_disallowedUser} is called.
 */
abstract contract ERC20Allowlist is ERC20 {
    /**
     * @dev Allowed status of addresses. True if allowed, False otherwise.
     */
    mapping(address account => bool) public allowed;

    /**
     * @dev Emitted when a `user` is allowed to transfer and approve.
     */
    event UserAllowed(address indexed user);

    /**
     * @dev Emitted when a user is disallowed.
     */
    event UserDisallowed(address indexed user);

    /**
     * @dev The operation failed because the user is already allowed.
     */

    /**
     * @dev The operation failed because the user is not allowed.
     */
    error UserIsNotAllowed(address indexed user);

    /**
     * @dev Allows a user to receive and transfer tokens, including minting and burning.
     * @param user The address of the user to allow.
     *
     */
    function _allowUser(address user) internal virtual {
        if(!allowed(user)) {
          allowed[user] = true;
          emit UserAllowed(user);
        }
    }

    /**
     * @dev Disallows a user.
     *
     */
    function _disallowUser(address user) internal virtual {
        if (allowed(user)) {
          allowed[user] = false;
          emit UserDisallowed(user);
        }
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && !allowed[from]) revert ERC20Disallowed(from);
        if (to != address(0) && !allowed[to]) revert ERC20Disallowed(to);
        super._update(from, to, value);
    }

function allowed(address account) public virtual returns (bool) {
  return _allowed[account];
}

    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual override {
        address owner = _msgSender();
        if (! _allowed[owner]) revert ERC20Disallowed(owner);
        super._approve(owner, spender, value, emitEvent);
    }
}
