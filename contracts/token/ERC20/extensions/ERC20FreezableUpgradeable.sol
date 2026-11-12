// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC7943Fungible} from "@openzeppelin/community-contracts/interfaces/IERC7943.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @dev Extension of {ERC20} that allows to implement a freezing
 * mechanism that can be managed by an authorized account with the
 * {_setFrozen} function.
 *
 * The freezing mechanism provides the guarantee to the contract owner
 * (e.g. a DAO or a well-configured multisig) that a specific amount
 * of tokens held by an account won't be transferable until the frozen amount
 * is reduced using {_setFrozen}.
 */
abstract contract ERC20FreezableUpgradeable is Initializable, ERC20Upgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.ERC20Freezable
    struct ERC20FreezableStorage {
        /// @dev Frozen amount of tokens per address.
        mapping(address account => uint256) _frozenBalances;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20Freezable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20FreezableStorageLocation = 0x583fad51f658d0abc059ba589bd4a25c62218b1e44997abfca1b43cfb31c7f00;

    function _getERC20FreezableStorage() private pure returns (ERC20FreezableStorage storage $) {
        assembly {
            $.slot := ERC20FreezableStorageLocation
        }
    }

    /// @dev The operation failed because the account has insufficient unfrozen balance.
    error ERC20InsufficientUnfrozenBalance(address account, uint256 needed, uint256 available);

    function __ERC20Freezable_init() internal onlyInitializing {
    }

    function __ERC20Freezable_init_unchained() internal onlyInitializing {
    }
    /// @dev Returns the frozen balance of an account.
    function frozen(address account) public view virtual returns (uint256) {
        ERC20FreezableStorage storage $ = _getERC20FreezableStorage();
        return $._frozenBalances[account];
    }

    /// @dev Returns the available (unfrozen) balance of an account. Up to {balanceOf}.
    function available(address account) public view virtual returns (uint256) {
        ERC20FreezableStorage storage $ = _getERC20FreezableStorage();
        (bool success, uint256 unfrozen) = Math.trySub(balanceOf(account), $._frozenBalances[account]);
        return success ? unfrozen : 0;
    }

    /// @dev Internal function to set the frozen token amount for a account.
    function _setFrozen(address account, uint256 amount) internal virtual {
        ERC20FreezableStorage storage $ = _getERC20FreezableStorage();
        $._frozenBalances[account] = amount;
        emit IERC7943Fungible.Frozen(account, amount);
    }

    /**
     * @dev See {ERC20-_update}.
     *
     * Requirements:
     *
     * * `from` must have sufficient unfrozen balance.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0)) {
            uint256 unfrozen = available(from);
            require(unfrozen >= value, ERC20InsufficientUnfrozenBalance(from, value, unfrozen));
        }
        super._update(from, to, value);
    }

    // We don't check frozen balance for approvals since the actual transfer
    // will be checked in _update. This allows for more flexible approval patterns.
}
