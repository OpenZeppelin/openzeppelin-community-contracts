// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {
    IScaledUIAmount,
    IScaledUIAmountNewUIMultiplier,
    IScaledUIAmountConversion,
    IScaledUIAmountBalances
} from "../../../interfaces/IERC8056.sol";

/**
 * @dev Extension of {ERC20} that implements https://eips.ethereum.org/EIPS/eip-8056[ERC-8056], a UI multiplier
 * that scales the amounts shown to users (e.g. to represent a stock split) without changing any balance.
 *
 * The multiplier is a display value only. Every ERC-20 value stays in raw units, including balances, allowances,
 * signed permits, votes, caps, frozen amounts and vault conversions. This extension does not override any ERC-20
 * function, so it composes with other extensions without changing their behavior.
 *
 * Multiplier updates are scheduled with {_setUIMultiplier} and take effect at a given timestamp. The multiplier is
 * stored per chain, so a token deployed on several chains should schedule the same update on each of them.
 *
 * NOTE: This contract does not emit the optional {IScaledUIAmount-TransferWithUIAmount} event. Developers can emit
 * it by overriding {_update}.
 *
 * IMPORTANT: {_setUIMultiplier} and {_cancelUIMultiplierUpdate} have no access control. ERC-8056 requires
 * implementations to restrict them to authorized accounts.
 */
abstract contract ERC20ScaledUIAmount is
    ERC20,
    ERC165,
    IScaledUIAmount,
    IScaledUIAmountNewUIMultiplier,
    IScaledUIAmountConversion,
    IScaledUIAmountBalances
{
    uint256 private constant MULTIPLIER_UNIT = 1e18;

    uint256 private _uiMultiplier = MULTIPLIER_UNIT;
    uint256 private _newUIMultiplier = MULTIPLIER_UNIT;
    uint48 private _effectiveAt;

    /// @dev The UI multiplier is zero.
    error ERC20ScaledUIAmountInvalidMultiplier(uint256 multiplier);

    /// @dev The scheduled timestamp is in the past.
    error ERC20ScaledUIAmountInvalidEffectiveAt(uint48 effectiveAt);

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IScaledUIAmount).interfaceId ||
            interfaceId == type(IScaledUIAmountNewUIMultiplier).interfaceId ||
            interfaceId == type(IScaledUIAmountConversion).interfaceId ||
            interfaceId == type(IScaledUIAmountBalances).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IScaledUIAmount
    function uiMultiplier() public view virtual returns (uint256) {
        return Time.timestamp() < _effectiveAt ? _uiMultiplier : _newUIMultiplier;
    }

    /// @inheritdoc IScaledUIAmountNewUIMultiplier
    function newUIMultiplier() public view virtual returns (uint256) {
        return _newUIMultiplier;
    }

    /// @inheritdoc IScaledUIAmountNewUIMultiplier
    function effectiveAt() public view virtual returns (uint256) {
        return _effectiveAt;
    }

    /// @inheritdoc IScaledUIAmountConversion
    function toUIAmount(uint256 rawAmount) public view virtual returns (uint256) {
        return Math.mulDiv(rawAmount, uiMultiplier(), MULTIPLIER_UNIT);
    }

    /// @dev See {IScaledUIAmountConversion-fromUIAmount}. Rounds down.
    function fromUIAmount(uint256 uiAmount) public view virtual returns (uint256) {
        return Math.mulDiv(uiAmount, MULTIPLIER_UNIT, uiMultiplier());
    }

    /// @inheritdoc IScaledUIAmountBalances
    function balanceOfUI(address account) public view virtual returns (uint256) {
        return toUIAmount(balanceOf(account));
    }

    /// @inheritdoc IScaledUIAmountBalances
    function totalSupplyUI() public view virtual returns (uint256) {
        return toUIAmount(totalSupply());
    }

    /**
     * @dev Schedules `newMultiplier` to become the UI multiplier at `effectiveAtTimestamp`. A pending update that has
     * not taken effect yet is superseded.
     *
     * Emits a {IScaledUIAmount-UIMultiplierUpdated} event, preceded by a {IScaledUIAmount-UIMultiplierUpdateCancelled}
     * event if a pending update is superseded.
     *
     * Requirements:
     *
     * * `newMultiplier` must not be zero.
     * * `effectiveAtTimestamp` must not be in the past.
     */
    function _setUIMultiplier(uint256 newMultiplier, uint48 effectiveAtTimestamp) internal virtual {
        require(newMultiplier > 0, ERC20ScaledUIAmountInvalidMultiplier(newMultiplier));
        require(effectiveAtTimestamp >= Time.timestamp(), ERC20ScaledUIAmountInvalidEffectiveAt(effectiveAtTimestamp));

        _cancelUIMultiplierUpdate();
        uint256 oldMultiplier = uiMultiplier();
        _uiMultiplier = oldMultiplier;
        _newUIMultiplier = newMultiplier;
        _effectiveAt = effectiveAtTimestamp;
        emit UIMultiplierUpdated(oldMultiplier, newMultiplier, effectiveAtTimestamp);
    }

    /**
     * @dev Cancels the pending UI multiplier update. Returns false if there is no update pending.
     *
     * Emits a {IScaledUIAmount-UIMultiplierUpdateCancelled} event if an update is cancelled.
     */
    function _cancelUIMultiplierUpdate() internal virtual returns (bool) {
        uint48 pendingEffectiveAt = _effectiveAt;
        if (Time.timestamp() >= pendingEffectiveAt) return false; // no pending update
        uint256 pendingMultiplier = _newUIMultiplier;
        _newUIMultiplier = _uiMultiplier;
        _effectiveAt = 0;
        emit UIMultiplierUpdateCancelled(pendingMultiplier, pendingEffectiveAt);
        return true;
    }
}
