// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC7943Fungible} from "../../../interfaces/IERC7943.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";
import {ERC20Freezable} from "./ERC20Freezable.sol";
import {ERC20Restricted} from "./ERC20Restricted.sol";

/**
 * @dev Extension of {ERC20} according to https://eips.ethereum.org/EIPS/eip-7943[EIP-7943].
 *
 * Combines standard ERC-20 functionality with RWA-specific features like account restrictions,
 * asset freezing, and forced asset transfers. This contract doesn't expose minting or burning
 * capabilities; if implemented in derived contracts as needed, they must include 7943-specific
 * logic.
 */
abstract contract ERC20uRWA is ERC20, ERC165, ERC20Freezable, ERC20Restricted, IERC7943Fungible {
    using TransientSlot for *;

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20uRWA")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20_URWA_FORCED_TRANSFER_SLOT =
        0x2f15ed3f796dcc08760ea3f28d5fdea0e800838283141b1cb98a3bdd04ef5400;

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC7943Fungible).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC7943Fungible-canSend}. Defaults to {ERC20Restricted-canSend}.
     *
     * Override to implement sender-specific restrictions distinct from {canReceive}.
     */
    function canSend(address account) public view virtual override(IERC7943Fungible, ERC20Restricted) returns (bool) {
        return super.canSend(account);
    }

    /**
     * @dev See {IERC7943Fungible-canReceive}. Defaults to {ERC20Restricted-canReceive}.
     *
     * Override to implement recipient-specific restrictions distinct from {canSend}.
     */
    function canReceive(
        address account
    ) public view virtual override(IERC7943Fungible, ERC20Restricted) returns (bool) {
        return super.canReceive(account);
    }

    /**
     * @dev See {IERC7943Fungible-canTransfer}.
     *
     * Returns false when the transfer is prevented by a permissioned rule: an `amount` exceeding
     * the unfrozen balance (only while covered by the current balance), or {canSend} / {canReceive}
     * restrictions. Plain balance insufficiency (`amount > balanceOf(from)`) does not return false
     * here, as those validations belong to the base ERC-20 standard per EIP-7943.
     *
     * CAUTION: This function is only meant for external use. Overriding it will not apply the new
     * checks to the internal {_update} function, which enforces {canSend}, {canReceive} and the
     * unfrozen balance directly. Consider overriding {_update} accordingly to keep both in sync.
     */
    function canTransfer(address from, address to, uint256 amount) external view virtual returns (bool) {
        return canSend(from) && canReceive(to) && (amount > balanceOf(from) || amount <= available(from));
    }

    /// @inheritdoc IERC7943Fungible
    function getFrozenTokens(address account) public view virtual returns (uint256 amount) {
        return frozen(account);
    }

    /**
     * @dev See {IERC7943Fungible-setFrozenTokens}. Always returns true if successful. Reverts otherwise.
     *
     * NOTE: The `amount` is allowed to exceed the current balance to support future balances withholding,
     * as required by the EIP-7943 spec.
     */
    function setFrozenTokens(address account, uint256 amount) public virtual returns (bool result) {
        _checkFreezer(account, amount);
        _setFrozen(account, amount);
        return true;
    }

    /**
     * @dev See {IERC7943Fungible-forcedTransfer}. Always returns true if successful. Reverts otherwise.
     *
     * Bypasses the {canSend} and {ERC20Restricted} checks for the `from` address and adjusts the
     * frozen balance to the new balance after the transfer. The recipient is still required to
     * pass the {canReceive} check, as recommended by EIP-7943.
     *
     * NOTE: This function uses {_update} to perform the transfer, ensuring all standard ERC20
     * side effects (such as balance updates and events) are preserved. If you override {_update}
     * to add additional restrictions or logic, those changes will also apply here.
     * Consider overriding this function to bypass newer restrictions if needed.
     *
     * NOTE: A forced transfer to self moves no tokens, so it performs no frozen balance adjustment
     * (otherwise it would act as an unauthorized unfreeze bypassing the freezer role). It behaves
     * as a regular ERC-20 self-transfer, reverting if `amount` exceeds the unfrozen balance.
     *
     * CAUTION: The sender-side and recipient-side checks are suppressed for the duration of the
     * internal {_update} call. If an override of {_update} performs external calls, a reentering
     * transfer will skip those checks as well. Consider adding reentrancy protection when
     * extending {_update} with external calls.
     */
    function forcedTransfer(address from, address to, uint256 amount) public virtual returns (bool result) {
        _checkEnforcer(from, to, amount);
        require(canReceive(to), ERC7943CannotReceive(to));

        // Update frozen balance if needed. ERC-7943 requires that balance is unfrozen first (emitting
        // the corresponding Frozen event via _setFrozen) and then send the tokens. Skipped for
        // self-transfers, where the balance does not change and no unfreeze is warranted.
        uint256 currentFrozen = frozen(from);
        uint256 newBalance;
        unchecked {
            // Safe because ERC20._update will check that balanceOf(from) >= amount
            newBalance = balanceOf(from) - amount;
        }
        if (from != to && currentFrozen > newBalance) {
            _setFrozen(from, newBalance);
        }

        // Temporarily flag the transfer as forced rather than calling ERC20._update directly.
        // This preserves any side effects from future overrides to _update while letting
        // _checkSend and _checkReceive skip the sender-side and recipient-side checks.
        ERC20_URWA_FORCED_TRANSFER_SLOT.asBoolean().tstore(true);
        _update(from, to, amount);
        ERC20_URWA_FORCED_TRANSFER_SLOT.asBoolean().tstore(false);
        emit ForcedTransfer(from, to, amount);
        return true;
    }

    /**
     * @dev See {ERC20-_update}. The inherited {ERC20Restricted} and {ERC20Freezable} checks apply,
     * with the sender-side and recipient-side eligibility enforced through {_checkSend} and
     * {_checkReceive}, so that public transfers cannot succeed in cases where {canTransfer} would
     * return false.
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Freezable, ERC20Restricted) {
        super._update(from, to, amount);
    }

    /**
     * @dev See {ERC20Restricted-_checkSend}. Reverts with {IERC7943Fungible-ERC7943CannotSend}.
     * Skipped during a {forcedTransfer} so that enforcement transfers can move tokens out of
     * restricted accounts.
     */
    function _checkSend(address account) internal view virtual override {
        if (!_isForcedTransfer()) require(canSend(account), ERC7943CannotSend(account));
    }

    /**
     * @dev See {ERC20Restricted-_checkReceive}. Reverts with {IERC7943Fungible-ERC7943CannotReceive}.
     * Skipped during a {forcedTransfer}, where the recipient has already been checked upfront.
     */
    function _checkReceive(address account) internal view virtual override {
        if (!_isForcedTransfer()) require(canReceive(account), ERC7943CannotReceive(account));
    }

    /// @dev Whether the current transfer is being performed by {forcedTransfer}.
    function _isForcedTransfer() internal view virtual returns (bool) {
        return ERC20_URWA_FORCED_TRANSFER_SLOT.asBoolean().tload();
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
     * function _checkFreezer(address account, uint256 amount) internal view override onlyRole(FREEZER_ROLE) {}
     * ```
     */
    function _checkFreezer(address account, uint256 amount) internal view virtual;
}
