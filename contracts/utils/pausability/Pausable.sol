// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/Pausable.sol)

pragma solidity ^0.8.20;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

uint8 constant PAUSED = 1;
uint8 constant UNPAUSED = 0;
uint48 constant NO_DEADLINE = 0;
uint8 constant PAUSE_DEADLINE_OFFSET = 8;

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
abstract contract Pausable is Context, IERC6372 {
    /**
     * @dev Storage slot is structured like so:
     *
     * - Least significant 8 bits: signal pause state.
     *   1 for paused, 0 for unpaused.
     *
     * - After, the following 48 bits: signal timestamp at which the contract
     *   will be automatically unpaused if the pause had a duration set.
     */
    uint256 private _pausedInfo;

    /**
     * @dev Emitted when the pause is triggered by `account`. `unpauseDeadline` is 0 if the pause is indefinite.
     */
    event Paused(address account, uint48 unpauseDeadline);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    /**
     * @dev The operation failed because the contract is not paused.
     */
    error ExpectedPause();

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _pausedInfo = UNPAUSED;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Clock is used here for time checkings on pauses with defined end-date.
     *
     * Override this function to implement a customed clock, if so must be done following
     * {IERC6372} specification.
     *
     * Default native `block.timetmap` clock implementation can be found at {DefaultPausable}.
     */
    function clock() public view virtual returns (uint48);

    /**
     * @dev IERC6372 implementation of a CLOCK_MODE().
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual returns (string memory);

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     *
     * A contract is paused (returns true) if:
     *
     * - It was paused by `_pause()`
     * - Or if it was paused by `_pauseUntil(uint256 unpauseDeadline)` and `unpauseDeadline`
     *  is still in the future.
     */
    function paused() public view virtual returns (bool) {
        uint48 unpauseDeadline = _unpauseDeadline();
        return _pausedInfo == PAUSED || (unpauseDeadline != 0 && clock() < unpauseDeadline);
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /**
     * @dev Returns the time date at which the contract will be automatically unpaused.
     *
     * If returned 0, the contract might or might not be paused.
     * This function must not be used for checking paused state.
     */
    function _unpauseDeadline() internal view virtual returns (uint48) {
        return uint48(_pausedInfo >> PAUSE_DEADLINE_OFFSET);
    }

    /**
     * @dev Triggers stopped state indefinitely.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _pausedInfo = PAUSED;
        emit Paused(_msgSender(), NO_DEADLINE);
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
        if (unpauseDeadline > clock()) {
            _pausedInfo = (uint256(unpauseDeadline) << PAUSE_DEADLINE_OFFSET) | PAUSED;
            emit Paused(_msgSender(), unpauseDeadline);
        }
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _pausedInfo = UNPAUSED;
        emit Unpaused(_msgSender());
    }
}
