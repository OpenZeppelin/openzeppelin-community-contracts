// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Extension of {ERC20} that allows to implement user account transfer restrictions
 * through the {isUserAllowed} function. Inspired by https://eips.ethereum.org/EIPS/eip-7943[EIP-7943].
 *
 * By default, each account has no explicit restriction. The {isUserAllowed} function acts as
 * a blocklist. Developers can override {isUserAllowed} to check that `restriction == ALLOWED`
 * to implement an allowlist.
 */
abstract contract ERC20Restricted is ERC20 {
    enum Restriction {
        DEFAULT, // User has no explicit restriction
        BLOCKED, // User is explicitly blocked
        ALLOWED // User is explicitly allowed
    }

    mapping(address account => Restriction) private _restrictions;

    /// @dev Emitted when a user account's restriction is updated.
    event UserRestrictionsUpdated(address indexed account, Restriction restriction);

    /// @dev The operation failed because the user account is restricted.
    error ERC20UserRestricted(address account);

    /// @dev Returns the restriction of a user account.
    function getRestriction(address account) public view virtual returns (Restriction) {
        return _restrictions[account];
    }

    /**
     * @dev Returns whether a user account is allowed to interact with the token.
     *
     * Default implementation only disallows explicitly BLOCKED accounts (i.e. a blocklist).
     *
     * To convert into an allowlist, override as:
     *
     * ```solidity
     * function isUserAllowed(address account) public view virtual override returns (bool) {
     *     return getRestriction(account) == Restriction.ALLOWED;
     * }
     * ```
     */
    function isUserAllowed(address account) public view virtual returns (bool) {
        return getRestriction(account) != Restriction.BLOCKED; // i.e. DEFAULT && ALLOWED
    }

    /**
     * @dev See {ERC20-_update}. Enforces restriction transfers (excluding minting and burning).
     *
     * Requirements:
     *
     * * `from` must be allowed to transfer tokens (see {isUserAllowed}).
     * * `to` must be allowed to receive tokens (see {isUserAllowed}).
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0)) _checkRestriction(from); // Not minting
        if (to != address(0)) _checkRestriction(to); // Not burning
        super._update(from, to, value);
    }

    // We don't check restrictions for approvals since the actual transfer
    // will be checked in _update. This allows for more flexible approval patterns.

    /// @dev Updates the restriction of a user account.
    function _setRestriction(address account, Restriction restriction) internal virtual {
        if (getRestriction(account) != restriction) {
            _restrictions[account] = restriction;
            emit UserRestrictionsUpdated(account, restriction);
        } // no-op if restriction is unchanged
    }

    /// @dev Convenience function to block a user account (set to BLOCKED).
    function _blockUser(address account) internal virtual {
        _setRestriction(account, Restriction.BLOCKED);
    }

    /// @dev Convenience function to allow a user account (set to ALLOWED).
    function _allowUser(address account) internal virtual {
        _setRestriction(account, Restriction.ALLOWED);
    }

    /// @dev Convenience function to reset a user account to default restriction.
    function _resetUser(address account) internal virtual {
        _setRestriction(account, Restriction.DEFAULT);
    }

    /// @dev Checks if a user account is restricted. Reverts with {ERC20Restricted} if so.
    function _checkRestriction(address account) internal view virtual {
        require(isUserAllowed(account), ERC20UserRestricted(account));
    }
}
