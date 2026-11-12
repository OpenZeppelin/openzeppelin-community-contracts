// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

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
 *
 * IMPORTANT: Deprecated. Use {ERC20Restricted} instead.
 */
abstract contract ERC20BlocklistUpgradeable is Initializable, ERC20Upgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.ERC20Blocklist
    struct ERC20BlocklistStorage {
        /**
         * @dev Blocked status of addresses. True if blocked, False otherwise.
         */
        mapping(address user => bool) _blocked;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20Blocklist")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20BlocklistStorageLocation = 0x67ea621d385b824937cc39f7f7c62944e59ef51b48daeabbb868c7df81010800;

    function _getERC20BlocklistStorage() private pure returns (ERC20BlocklistStorage storage $) {
        assembly {
            $.slot := ERC20BlocklistStorageLocation
        }
    }

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

    function __ERC20Blocklist_init() internal onlyInitializing {
    }

    function __ERC20Blocklist_init_unchained() internal onlyInitializing {
    }
    /**
     * @dev Returns the blocked status of an account.
     */
    function blocked(address account) public virtual returns (bool) {
        ERC20BlocklistStorage storage $ = _getERC20BlocklistStorage();
        return $._blocked[account];
    }

    /**
     * @dev Blocks a user from receiving and transferring tokens, including minting and burning.
     */
    function _blockUser(address user) internal virtual returns (bool) {
        ERC20BlocklistStorage storage $ = _getERC20BlocklistStorage();
        bool isBlocked = blocked(user);
        if (!isBlocked) {
            $._blocked[user] = true;
            emit UserBlocked(user);
        }
        return isBlocked;
    }

    /**
     * @dev Unblocks a user from receiving and transferring tokens, including minting and burning.
     */
    function _unblockUser(address user) internal virtual returns (bool) {
        ERC20BlocklistStorage storage $ = _getERC20BlocklistStorage();
        bool isBlocked = blocked(user);
        if (isBlocked) {
            $._blocked[user] = false;
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
