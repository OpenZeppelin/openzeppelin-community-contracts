// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC7943Fungible} from "../../../interfaces/IERC7943.sol";
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
abstract contract ERC20uRWA is ERC20, ERC165, ERC20Freezable, ERC20Restricted, IERC7943Fungible {
    /// @inheritdoc ERC20Restricted
    function isUserAllowed(
        address user
    ) public view virtual override(IERC7943Fungible, ERC20Restricted) returns (bool) {
        return super.isUserAllowed(user);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC7943Fungible).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC7943Fungible-canTransfer}.
     *
     * CAUTION: This function is only meant for external use. Overriding it will not apply the new checks to
     * the internal {_update} function. Consider overriding {_update} accordingly to keep both functions in sync.
     */
    function canTransfer(address from, address to, uint256 amount) external view virtual returns (bool) {
        return (amount <= available(from) && isUserAllowed(from) && isUserAllowed(to));
    }

    /// @inheritdoc IERC7943Fungible
    function getFrozenTokens(address user) public view virtual returns (uint256 amount) {
        return frozen(user);
    }

    /**
     * @dev See {IERC7943Fungible-setFrozenTokens}.
     *
     * NOTE: The `amount` is capped to the balance of the `user` to ensure the {IERC7943Fungible-Frozen} event
     * emits values that consistently reflect the actual amount of tokens that are frozen.
     */
    function setFrozenTokens(address user, uint256 amount) public virtual {
        uint256 actualAmount = Math.min(amount, balanceOf(user));
        _checkFreezer(user, actualAmount);
        _setFrozen(user, actualAmount);
    }

    /**
     * @dev See {IERC7943Fungible-forcedTransfer}.
     *
     * Bypasses the {ERC20Restricted} restrictions for the `from` address and adjusts the frozen balance
     * to the new balance after the transfer.
     *
     * NOTE: This function uses {_update} to perform the transfer, ensuring all standard ERC20
     * side effects (such as balance updates and events) are preserved. If you override {_update}
     * to add additional restrictions or logic, those changes will also apply here.
     * Consider overriding this function to bypass newer restrictions if needed.
     */
    function forcedTransfer(address from, address to, uint256 amount) public virtual {
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

        // Temporarily bypass restrictions rather than calling ERC20._update directly.
        // This preserves any side effects from future overrides to _update.
        // Assuming `forcedTransfer` will be used occasionally, the added costs of temporary
        // restrictions would be justifiable under this path.
        Restriction restriction = getRestriction(from);
        bool wasUserAllowed = isUserAllowed(from);
        if (!wasUserAllowed) _setRestriction(from, Restriction.ALLOWED);
        _update(from, to, amount); // Explicit raw update to bypass all restrictions
        if (!wasUserAllowed) _setRestriction(from, restriction);
        emit ForcedTransfer(from, to, amount);
    }

    /// @inheritdoc ERC20
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Freezable, ERC20Restricted) {
        // Note: We rely on the inherited _update chain (ERC20Freezable + ERC20Restricted) to enforce
        // the same restrictions that isTransferAllowed would check. This avoids duplicate validation
        // while maintaining consistency between external queries and internal transfer logic.
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
