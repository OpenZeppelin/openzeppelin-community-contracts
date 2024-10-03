// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Extension of {ERC20} that allows to implement an allowlist
 * mechanism that can be managed by an authorized account.
 * The allowlist provides the guarantee to the contract owner (e.g. a DAO or a well-configured multisig)
 * that any account won't be able to execute transfers or approvals to other entities to operate on
 * its behalf if {_allowUser} was not called with such account as an argument. Similarly, the account
 * will be blocked again if {_disallowedUser} is called.
 * This module is used through inheritance. It will make available the
 * functions `allowUser` and `disallowUser`, which can be used to
 * manage the allowlist in your contract.
 */
abstract contract ERC20Allowlist is ERC20 {
    /**
     * @dev Allowed status of addresses. True if allowed, False otherwise.
     */
    mapping(address => bool) public allowed;

    /**
     * @dev Emitted when a user is allowed.
     * @param user The address of the user that was allowed.
     */
    event UserAllowed(address indexed user);

    /**
     * @dev Emitted when a user is disallowed.
     * @param user The address of the user that was disallowed.
     */
    event UserDisallowed(address indexed user);

    /**
     * @dev The operation failed because the user is already allowed.
     */
    error UserIsAllowed();

    /**
     * @dev The operation failed because the user is not allowed.
     * @param user The address of the user that is not allowed.
     */
    error UserIsNotAllowed(address user);

    /**
     * @dev Allows a user to receive and transfer tokens, including minting and burning.
     * @param user The address of the user to allow.
     *
     * Requirements:
     *
     * - The user must not be already allowed.
     */
    function _allowUser(address user) internal virtual {
        if (allowed[user]) revert UserIsAllowed();
        allowed[user] = true;
        emit UserAllowed(user);
    }

    /**
     * @dev Disallows a user.
     * @param user The address of the user to disallow.
     *
     * Requirements:
     *
     * - The user must be allowed.
     */
    function _disallowUser(address user) internal virtual {
        if (!allowed[user]) revert UserIsNotAllowed(user);
        allowed[user] = false;
        emit UserDisallowed(user);
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && !allowed[from]) revert UserIsNotAllowed(from);
        if (to != address(0) && !allowed[to]) revert UserIsNotAllowed(to);
        super._update(from, to, value);
    }

    function approve(address spender, uint256 value) public virtual override returns (bool) {
        address owner = _msgSender();
        if (!allowed[owner]) revert UserIsNotAllowed(owner);
        _approve(owner, spender, value);
        return true;
    }
}
