// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @dev Extension of {ERC20} that allows to implement user account transfer restrictions
 * through the {canTransact} function. Inspired by https://eips.ethereum.org/EIPS/eip-7943[EIP-7943].
 *
 * By default, each account has no explicit restriction. The {canTransact} function acts as
 * a blocklist. Developers can override {canTransact} to check that `restriction == ALLOWED`
 * to implement an allowlist.
 */
abstract contract ERC20RestrictedUpgradeable is Initializable, ERC20Upgradeable {
    enum Restriction {
        DEFAULT, // User has no explicit restriction
        BLOCKED, // User is explicitly blocked
        ALLOWED // User is explicitly allowed
    }

    /// @custom:storage-location erc7201:openzeppelin.storage.ERC20Restricted
    struct ERC20RestrictedStorage {
        mapping(address account => Restriction) _restrictions;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20Restricted")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20RestrictedStorageLocation = 0x572a0f5339991a4a4f7c71b7ba3c6c0b55f542bbb9159cae4efc1f6074ea7b00;

    function _getERC20RestrictedStorage() private pure returns (ERC20RestrictedStorage storage $) {
        assembly {
            $.slot := ERC20RestrictedStorageLocation
        }
    }

    /// @dev Emitted when a user account's restriction is updated.
    event UserRestrictionsUpdated(address indexed account, Restriction restriction);

    /// @dev The operation failed because the user account is restricted.
    error ERC20UserRestricted(address account);

    function __ERC20Restricted_init() internal onlyInitializing {
    }

    function __ERC20Restricted_init_unchained() internal onlyInitializing {
    }
    /// @dev Returns the restriction of a user account.
    function getRestriction(address account) public view virtual returns (Restriction) {
        ERC20RestrictedStorage storage $ = _getERC20RestrictedStorage();
        return $._restrictions[account];
    }

    /**
     * @dev Returns whether a user account is allowed to interact with the token.
     *
     * Default implementation only disallows explicitly BLOCKED accounts (i.e. a blocklist).
     *
     * To convert into an allowlist, override as:
     *
     * ```solidity
     * function canTransact(address account) public view virtual override returns (bool) {
     *     return getRestriction(account) == Restriction.ALLOWED;
     * }
     * ```
     */
    function canTransact(address account) public view virtual returns (bool) {
        return getRestriction(account) != Restriction.BLOCKED; // i.e. DEFAULT && ALLOWED
    }

    /**
     * @dev See {ERC20-_update}. Enforces restriction transfers (excluding minting and burning).
     *
     * Requirements:
     *
     * * `from` must be allowed to transfer tokens (see {canTransact}).
     * * `to` must be allowed to receive tokens (see {canTransact}).
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
        ERC20RestrictedStorage storage $ = _getERC20RestrictedStorage();
        if (getRestriction(account) != restriction) {
            $._restrictions[account] = restriction;
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
        require(canTransact(account), ERC20UserRestricted(account));
    }
}
