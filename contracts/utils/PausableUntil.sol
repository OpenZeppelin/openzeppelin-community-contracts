// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

/**
 * @title Pausable
 * @author @CarlosAlegreUr
 *
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * Stops can be of undefined duration or for a certain amount of time.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be `Pausable` by
 * simply including this module, only once the modifiers are put in place
 * and access to call the internal `_pause()`, `_unpause()`, `_pauseUntil()`
 * functions is coded.
 *
 * [ ⚠️ WARNING ⚠️ ]
 * This version should be backwards compatible with previous OpenZeppelin `Pausable`
 * versions as it uses the same 1 storage slot in a backwards compatible way.
 *
 * However this has not been tested yet. Please test locally before updating any
 * contract to use this version.
 */
abstract contract PausableUntil is Pausable, IERC6372 {
    /**
     * @dev Storage slot is structured like so:
     *
     * - Least significant 8 bits: signal pause state.
     *   1 for paused, 0 for unpaused.
     *
     * - After, the following 48 bits: signal timestamp at which the contract
     *   will be automatically unpaused if the pause had a duration set.
     */
    uint48 private _pausedUntil;

    /**
     * @dev Emitted when the pause is triggered by `account`. `unpauseDeadline` is 0 if the pause is indefinite.
     */
    event Paused(address account, uint48 unpauseDeadline);

    /**
     * @inheritdoc IERC6372
     */
    function clock() public view virtual returns (uint48);

    /**
     * @dev Returns the time date at which the contract will be automatically unpaused.
     *
     * If returned 0, the contract might or might not be paused.
     * This function must not be used for checking paused state.
     */
    function _unpauseDeadline() internal view virtual returns (uint48) {
        return _pausedUntil;
    }

    /**
     * @dev Triggers stopped state while `unpauseDeadline` date is still in the future.
     *
     * This function should be used to prevent eternally pausing contracts in complex
     * permissioned systems.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     * - `unpauseDeadline` must be in the future.
     * - `clock()` return value and `unpauseDeadline` must be in the same time units.
     * - If pausing with an `unpauseDeadline` in the past this function will not pause neither revert.
     */
    function _pauseUntil(uint48 unpauseDeadline) internal virtual whenNotPaused {
        _pausedUntil = unpauseDeadline;
        emit Paused(_msgSender(), unpauseDeadline);
    }

    /**
     * @inheritdoc Pausable
     */
    function paused() public view virtual override returns (bool) {
        // exit early without an sload if normal paused is enabled
        if (super.paused()) return true;

        uint48 unpauseDeadline = _unpauseDeadline();
        return unpauseDeadline != 0 && this.clock() < unpauseDeadline;
    }

    /**
     * @inheritdoc Pausable
     */
    function _pause() internal virtual override {
        super._pause();
        delete _pausedUntil;
    }

    /**
     * @inheritdoc Pausable
     */
    function _unpause() internal virtual override {
        super._unpause();
        delete _pausedUntil;
    }
}
