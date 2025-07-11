// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC7943} from "../../../interfaces/IERC7943.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ERC20Freezable} from "./ERC20Freezable.sol";
import {ERC20Restricted} from "./ERC20Restricted.sol";

/**
 * @dev Extension of {ERC20} according to https://eips.ethereum.org/EIPS/eip-7943[EIP-7943].
 *
 * Combines standard ERC-20 functionality with RWA-specific features like user restrictions,
 * asset freezing, and forced asset transfers.
 */
// solhint-disable-next-line contract-name-capwords
abstract contract uRWA20 is ERC20, ERC165, ERC20Freezable, ERC20Restricted, IERC7943 {
    /// @inheritdoc ERC20Restricted
    function isUserAllowed(address user) public view virtual override(IERC7943, ERC20Restricted) returns (bool) {
        return super.isUserAllowed(user);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC7943).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IERC7943
    function isTransferAllowed(address from, address to, uint256, uint256 amount) public view virtual returns (bool) {
        return (amount <= available(from) && isUserAllowed(from) && isUserAllowed(to));
    }

    /// @inheritdoc IERC7943
    function getFrozen(address user, uint256) public view virtual returns (uint256 amount) {
        return frozen(user);
    }

    /// @inheritdoc IERC7943
    function setFrozen(address user, uint256, uint256 amount) public virtual {
        require(amount <= balanceOf(user), ERC20InsufficientBalance(user, balanceOf(user), amount));
        _checkFreezer(user, amount);
        _setFrozen(user, amount);
    }

    /// @inheritdoc IERC7943
    function forceTransfer(address from, address to, uint256, uint256 amount) public virtual {
        require(isUserAllowed(to), ERC7943NotAllowedUser(to));
        _checkEnforcer(from, to, amount);

        // Update frozen balance if needed
        uint256 currentFrozen = frozen(from);
        uint256 currentBalance = balanceOf(from);
        if (currentFrozen > currentBalance - amount) {
            _setFrozen(from, currentBalance - amount);
        }

        ERC20._update(from, to, amount); // Explicit raw update to bypass all restrictions
        emit ForcedTransfer(from, to, 0, amount);
    }

    /**
     * @dev See {ERC20-_update}.
     *
     * Requirements:
     *
     * * `from` and `to` must be allowed to transfer `amount` tokens (see {isTransferAllowed}).
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Freezable, ERC20Restricted) {
        if (from == address(0)) {
            // Minting
            require(isUserAllowed(to), ERC7943NotAllowedUser(to));
        } else if (to != address(0)) {
            // Transfer
            require(isTransferAllowed(from, to, 0, amount), ERC7943NotAllowedTransfer(from, to, 0, amount));
        }
        super._update(from, to, amount);
    }

    /**
     * @dev Internal function to check if the enforcer is allowed to force transfer.
     *
     * Example usage with {AccessControl-onlyRole}:
     *
     * ```solidity
     * function _checkEnforcer(address from, address to, uint256 amount) internal view override onlyRole(ENFORCER_ROLE) {}
     * ```
     */
    function _checkEnforcer(address from, address to, uint256 amount) internal view virtual;

    /**
     * @dev Internal function to check if the user has sufficient unfrozen balance.
     *
     * Example usage with {AccessControl-onlyRole}:
     *
     * ```solidity
     * function _checkFreezer(address user, uint256 amount) internal view override onlyRole(FREEZER_ROLE) {}
     * ```
     */
    function _checkFreezer(address user, uint256 amount) internal view virtual;
}
