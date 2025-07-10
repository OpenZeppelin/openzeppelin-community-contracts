// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC7943} from "../../../interfaces/IERC7943.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ERC20Freezable} from "./ERC20Freezable.sol";

/**
 * @dev Extension of {ERC20} according to https://eips.ethereum.org/EIPS/eip-7943[EIP-7943].
 *
 * Combines standard ERC-20 functionality with RWA-specific features like allowlist,
 * blocklist, controlled minting/burning, and forced asset transfers.
 *
 * ERC-7943 requires implementing {isUserAllowed} function which should be based on
 * your chosen user control mechanism. We recommend using {ERC20Allowlist} or {ERC20Blocklist}
 * for this.
 *
 * ```solidity
 * // Using ERC20Allowlist
 * contract MyuRWA20 is uRWA20, ERC20Allowlist {
 *     function isUserAllowed(address user) public view virtual override returns (bool) {
 *         return allowed(user);
 *     }
 * }
 *
 * // Using ERC20Blocklist
 * contract MyuRWA20 is uRWA20, ERC20Blocklist {
 *     function isUserAllowed(address user) public view virtual override returns (bool) {
 *         return !blocked(user);
 *     }
 * }
 * ```
 */
// solhint-disable-next-line contract-name-capwords
abstract contract uRWA20 is Context, ERC20, ERC20Freezable, IERC7943 {
    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC7943).interfaceId;
    }

    /// @inheritdoc IERC7943
    function isTransferAllowed(address from, address to, uint256, uint256 amount) public view virtual returns (bool) {
        return (amount <= available(from) && isUserAllowed(from) && isUserAllowed(to));
    }

    /// @inheritdoc IERC7943
    function isUserAllowed(address user) public view virtual returns (bool);

    /// @inheritdoc IERC7943
    function getFrozen(address user, uint256) public view virtual returns (uint256 amount) {
        return frozen(user);
    }

    /// @inheritdoc IERC7943
    function forceTransfer(address from, address to, uint256, uint256 amount) public virtual {
        _checkEnforcer(from, to, amount);

        // Update frozen balance if needed
        uint256 unfrozen = available(from);
        if (amount > unfrozen) {
            _setFrozen(from, unfrozen);
        }

        super._update(from, to, amount);
        emit ForcedTransfer(from, to, 0, amount);
    }

    /**
     * @dev See {ERC20-_update}.
     *
     * Requirements:
     *
     * * `from` must be allowed to transfer tokens (see {isUserAllowed}).
     * * `to` must be allowed to receive tokens (see {isUserAllowed}).
     * * `amount` must be available to transfer (see {_validateAvailable}).
     * * `from` and `to` must be allowed to transfer `amount` tokens (see {isTransferAllowed}).
     */
    function _update(address from, address to, uint256 amount) internal virtual override {
        require(from != address(0) && isUserAllowed(from), ERC7943NotAllowedUser(from)); // Discard minting
        require(to != address(0) && isUserAllowed(to), ERC7943NotAllowedUser(to)); // Discard burning
        require(amount <= available(from), ERC7943InsufficientUnfrozenBalance(from, 0, amount, available(from)));
        require(isTransferAllowed(from, to, 0, amount), ERC7943NotAllowedTransfer(from, to, 0, amount));

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
}
