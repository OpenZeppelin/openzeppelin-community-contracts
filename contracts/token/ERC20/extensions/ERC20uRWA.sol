// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC7943} from "../../../interfaces/IERC7943.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20Freezable} from "./ERC20Freezable.sol";
import {ERC20Restricted} from "./ERC20Restricted.sol";

/**
 * @dev Extension of {ERC20} according to https://eips.ethereum.org/EIPS/eip-7943[EIP-7943].
 *
 * Combines standard ERC-20 functionality with RWA-specific features like user restrictions,
 * asset freezing, and forced asset transfers.
 */
abstract contract ERC20uRWA is ERC20, ERC165, ERC20Freezable, ERC20Restricted, IERC7943 {
    /// @inheritdoc ERC20Restricted
    function isUserAllowed(address user) public view virtual override(IERC7943, ERC20Restricted) returns (bool) {
        return super.isUserAllowed(user);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC7943).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC7943-isTransferAllowed}.
     *
     * CAUTION: This function is only meant for external use. Overriding it will not apply the new checks to
     * the internal {_update} function. Consider overriding {_update} accordingly to keep both functions in sync.
     */
    function isTransferAllowed(address from, address to, uint256, uint256 amount) external view virtual returns (bool) {
        return (amount <= available(from) && isUserAllowed(from) && isUserAllowed(to));
    }

    /// @inheritdoc IERC7943
    function getFrozen(address user, uint256) public view virtual returns (uint256 amount) {
        return frozen(user);
    }

    /// @inheritdoc IERC7943
    function setFrozen(address user, uint256, uint256 amount) public virtual {
        uint256 actualAmount = Math.min(amount, balanceOf(user));
        _checkFreezer(user, actualAmount);
        _setFrozen(user, actualAmount);
    }

    /// @inheritdoc IERC7943
    function forceTransfer(address from, address to, uint256, uint256 amount) public virtual {
        _checkEnforcer(from, to, amount);
        require(isUserAllowed(to), ERC7943NotAllowedUser(to));

        // Update frozen balance if needed. ERC-7943 requires that balance is unfrozen first and then send the tokens.
        uint256 currentFrozen = frozen(from);
        uint256 newBalance;
        unchecked {
            // Safe because ERC20._update will check that balanceOf(from) >= amount
            newBalance = balanceOf(from) - amount;
        }
        if (currentFrozen > newBalance) {
            _setFrozen(from, newBalance);
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
        }
        // Note that `isTransferAllowed` duplicates the `available` check made by `super._update` in ERC20Freezable,
        // so, the following line is not needed but left for reference even though isTransferAllowed is external:
        // require(isTransferAllowed(from, to, 0, amount), ERC7943NotAllowedTransfer(from, to, 0, amount));
        super._update(from, to, amount);
    }

    /**
     * @dev Internal function to check if the `enforcer` is allowed to forcibly transfer the `amount` of `tokens`.
     *
     * Example usage with {AccessControl-onlyRole}:
     *
     * ```solidity
     * function _checkEnforcer(address from, address to, uint256 amount) internal view override onlyRole(ENFORCER_ROLE) {}
     * ```
     */
    function _checkEnforcer(address from, address to, uint256 amount) internal view virtual;

    /**
     * @dev Internal function to check if the `freezer` is allowed to freeze the `amount` of `tokens`.
     *
     * Example usage with {AccessControl-onlyRole}:
     *
     * ```solidity
     * function _checkFreezer(address user, uint256 amount) internal view override onlyRole(FREEZER_ROLE) {}
     * ```
     */
    function _checkFreezer(address user, uint256 amount) internal view virtual;
}
