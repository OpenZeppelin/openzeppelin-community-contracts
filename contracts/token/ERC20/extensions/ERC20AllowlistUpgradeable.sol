// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @dev Extension of {ERC20} that allows to implement an allowlist
 * mechanism that can be managed by an authorized account with the
 * {_disallowUser} and {_allowUser} functions.
 *
 * The allowlist provides the guarantee to the contract owner
 * (e.g. a DAO or a well-configured multisig) that any account won't be
 * able to execute transfers or approvals to other entities to operate
 * on its behalf if {_allowUser} was not called with such account as an
 * argument. Similarly, the account will be disallowed again if
 * {_disallowUser} is called.
 *
 * IMPORTANT: Deprecated. Use {ERC20Restricted} instead.
 */
abstract contract ERC20AllowlistUpgradeable is Initializable, ERC20Upgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.ERC20Allowlist
    struct ERC20AllowlistStorage {
        /**
         * @dev Allowed status of addresses. True if allowed, False otherwise.
         */
        mapping(address account => bool) _allowed;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20Allowlist")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20AllowlistStorageLocation = 0xe287d91c8c9f2f0d5e85866671148a670de112f42b7a77d09ae65e27e14ebe00;

    function _getERC20AllowlistStorage() private pure returns (ERC20AllowlistStorage storage $) {
        assembly {
            $.slot := ERC20AllowlistStorageLocation
        }
    }

    /**
     * @dev Emitted when a `user` is allowed to transfer and approve.
     */
    event UserAllowed(address indexed user);

    /**
     * @dev Emitted when a user is disallowed.
     */
    event UserDisallowed(address indexed user);

    /**
     * @dev The operation failed because the user is not allowed.
     */
    error ERC20Disallowed(address user);

    function __ERC20Allowlist_init() internal onlyInitializing {
    }

    function __ERC20Allowlist_init_unchained() internal onlyInitializing {
    }
    /**
     * @dev Returns the allowed status of an account.
     */
    function allowed(address account) public view virtual returns (bool) {
        ERC20AllowlistStorage storage $ = _getERC20AllowlistStorage();
        return $._allowed[account];
    }

    /**
     * @dev Allows a user to receive and transfer tokens, including minting and burning.
     */
    function _allowUser(address user) internal virtual returns (bool) {
        ERC20AllowlistStorage storage $ = _getERC20AllowlistStorage();
        bool isAllowed = allowed(user);
        if (!isAllowed) {
            $._allowed[user] = true;
            emit UserAllowed(user);
        }
        return isAllowed;
    }

    /**
     * @dev Disallows a user from receiving and transferring tokens, including minting and burning.
     */
    function _disallowUser(address user) internal virtual returns (bool) {
        ERC20AllowlistStorage storage $ = _getERC20AllowlistStorage();
        bool isAllowed = allowed(user);
        if (isAllowed) {
            $._allowed[user] = false;
            emit UserDisallowed(user);
        }
        return isAllowed;
    }

    /**
     * @dev See {ERC20-_update}.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && !allowed(from)) revert ERC20Disallowed(from);
        if (to != address(0) && !allowed(to)) revert ERC20Disallowed(to);
        super._update(from, to, value);
    }

    /**
     * @dev See {ERC20-_approve}.
     */
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual override {
        if (!allowed(owner)) revert ERC20Disallowed(owner);
        super._approve(owner, spender, value, emitEvent);
    }
}
