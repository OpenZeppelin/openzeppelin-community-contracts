// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Mode} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {ERC7579Executor} from "./ERC7579Executor.sol";

/**
 * @dev Extension of {ERC7579Executor} that allows scheduling and executing delayed operations
 * with expiration. This module enables time-delayed execution patterns for smart accounts.
 *
 * Once scheduled (see {schedule}), operations can only be executed after their specified delay
 * period has elapsed (indicated during {onInstall}), creating a security window where suspicious
 * operations can be monitored and potentially canceled (see {cancel}) before execution (see {execute}).
 *
 * Accounts can customize their delay periods with {setDelay}, Delay changes take effect after a
 * transition period to prevent immediate security downgrades.
 *
 * Operations have an expiration mechanism that prevents them from being executed after a certain
 * time has passed. It can be customized by overriding the {expiration} function and defaults to
 * `type(uint32).max` (no expiration).
 *
 * IMPORTANT: This module assumes the {AccountERC7579} is the ultimate authority and does not restrict
 * module uninstallation. An account can bypass the time-delay security by simply uninstalling
 * the module. Consider adding safeguards in your Account implementation if uninstallation
 * protection is required for your security model.
 */
abstract contract ERC7579DelayedExecutor is ERC7579Executor {
    using Time for *;

    uint32 private constant NO_DELAY = type(uint32).max; // Sentinel value for no delay
    uint32 private constant EXECUTED = type(uint32).max - 1; // Sentinel value for no delay

    // Invariant `delay` <= `expiration` < `type(uint32).max - 1` (for NO_DELAY and EXECUTED)
    struct Schedule {
        uint48 scheduledAt; // The time when the operation was scheduled
        uint32 delay; // Time after the operation becomes executable
        uint32 expiration; // Time after the operation expires
    }

    struct ExecutionConfig {
        Time.Delay delay;
        Time.Delay expiration;
    }

    mapping(address account => ExecutionConfig) private _config;
    mapping(bytes32 operationId => Schedule) private _schedules;

    /// @dev Emitted when a new operation is scheduled.
    event ERC7579ExecutorOperationScheduled(
        address indexed account,
        bytes32 indexed operationId,
        Mode mode,
        bytes executionCalldata,
        bytes32 salt,
        uint48 schedule
    );

    /// @dev Emitted when a scheduled operation is canceled.
    event ERC7579ExecutorOperationCanceled(address indexed account, bytes32 indexed operationId);

    /// @dev Emitted when the execution delay is updated.
    event ERC7579ExecutorDelayUpdated(address indexed account, uint32 newDelay, uint48 effectTime);

    /// @dev Emitted when the expiration delay is updated.
    event ERC7579ExecutorExpirationUpdated(address indexed account, uint32 newExpiration, uint48 effectTime);

    /// @dev Thrown when the account already installed the module.
    error ERC7579ExecutorAlreadyInstalled(address account);

    /// @dev Thrown when trying to execute an operation that is not scheduled.
    error ERC7579ExecutorOperationNotScheduled(bytes32 operationId);

    /// @dev Thrown when trying to execute an operation before its execution time.
    error ERC7579ExecutorOperationNotReady(bytes32 operationId, uint48 schedule);

    /// @dev Thrown when trying to schedule an operation that is already scheduled.
    error ERC7579ExecutorOperationAlreadyScheduled(bytes32 operationId);

    /// @dev Thrown when trying to execute an operation that has already been executed.
    error ERC7579ExecutorOperationAlreadyExecuted(bytes32 operationId);

    /// @dev Thrown when trying to execute an operation that has expired.
    error ERC7579ExecutorOperationExpired(bytes32 operationId, uint48 expiresAt);

    /// @dev Minimum delay for operations. Default for accounts that do not set a custom delay.
    function minimumDelay() public view virtual returns (uint32) {
        return 1 days; // Up to ~136 years
    }

    /// @dev Minimum expiration for operations. Default for accounts that do not set a custom expiration.
    function minimumExpiration() public view virtual returns (uint32) {
        return 365 days; // Up to ~136 years
    }

    /// @dev Delay for a specific account. If not set, returns the minimum delay.
    function getDelay(
        address account
    ) public view virtual returns (uint32 delay, uint32 pendingDelay, uint48 effectTime) {
        (uint32 currentDelay, uint32 newDelay, uint48 effect) = _config[account].delay.getFull();
        return (
            // Safe downcast since both arguments are uint32
            uint32(Math.ternary(_isDelayUninstalled(currentDelay), 0, Math.max(currentDelay, minimumDelay()))),
            newDelay,
            effect
        );
    }

    /// @dev Delay for a specific account. If not set, returns the minimum delay.
    function getExpiration(
        address account
    ) public view virtual returns (uint32 expiration, uint32 pendingExpiration, uint48 effectTime) {
        (uint32 currentDelay, uint32 newDelay, uint48 effect) = _config[account].expiration.getFull();
        return (
            // Safe downcast since both arguments are uint32
            uint32(Math.ternary(_isDelayUninstalled(currentDelay), 0, Math.max(currentDelay, minimumExpiration()))),
            newDelay,
            effect
        );
    }

    /**
     * @dev Schedule for an operation. Returns default values if not set
     * (i.e. `uint48(0)`, `uint48(0)`, `uint48(0)`, and `false`).
     */
    function getSchedule(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) public view virtual returns (uint48 scheduledAt, uint48 executableAt, uint48 expiresAt, bool executed) {
        return getSchedule(hashOperation(account, mode, executionCalldata, salt));
    }

    /// @dev Same as {getSchedule} but with the operation id.
    function getSchedule(
        bytes32 operationId
    ) public view virtual returns (uint48 scheduledAt, uint48 executableAt, uint48 expiresAt, bool executed) {
        Schedule storage schedule_ = _schedules[operationId];
        scheduledAt = schedule_.scheduledAt;
        uint32 delay = schedule_.delay;
        return (scheduledAt, scheduledAt + delay, scheduledAt + schedule_.expiration, delay == EXECUTED);
    }

    /// @dev Returns the operation id.
    function hashOperation(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) public view virtual returns (bytes32) {
        return keccak256(abi.encode(account, mode, executionCalldata, salt));
    }

    /**
     * @dev Sets up the module's initial configuration when installed by an account.
     * The account calling this function becomes registered with the module.
     *
     * The `initData` can contain an `abi.encode(uint32(initialDelay))` value.
     * The delay will be set to the maximum of this value and the minimum delay if provided.
     * Otherwise, the delay will be set to the minimum delay.
     *
     * Requirements:
     *
     * * The account must not have the module installed already. See {ERC7579ExecutorAlreadyInstalled}.
     * * The delay must be different to `type(uint32).max` used as a sentinel value for no delay.
     *
     * IMPORTANT: A delay will be set for the calling account. In case the account calls this function
     * directly, the delay will be set to the provided data even if the account didn't track
     * the module's installation. Future installations will revert.
     */
    function onInstall(bytes calldata initData) public virtual {
        (uint32 currentDelay, , ) = getDelay(msg.sender);
        require(_isDelayUninstalled(currentDelay), ERC7579ExecutorAlreadyInstalled(msg.sender));
        (uint32 delay, uint32 expiration) = initData.length > 0 ? abi.decode(initData, (uint32, uint32)) : (0, 0);
        _setDelay(msg.sender, uint32(Math.max(minimumDelay(), delay))); // Safe downcast since both arguments are uint32
        _setExpiration(msg.sender, uint32(Math.max(minimumExpiration(), expiration))); // Safe downcast since both arguments are uint32
    }

    /**
     * @dev Cleans up the {getDelay} and {getExpiration} values by scheduling them to `0`
     * and respecting the previous delay and expiration values. Do not consider {minimumDelay} and
     * {minimumExpiration} for scheduling.
     *
     * IMPORTANT: This function does not clean up scheduled operations. This means operations
     * could potentially be re-executed if the module is reinstalled later. This is a deliberate
     * design choice, but module implementations may want to override this behavior to clear
     * scheduled operations during uninstallation for their specific use cases.
     *
     * WARNING: The account's delay will be removed if the account calls this function, allowing
     * immediate scheduling of operations. As an account operator, make sure to uninstall to a
     * predefined path in your account that properly handles the side effects of uninstallation.
     * See {AccountERC7579-uninstallModule}.
     */
    function onUninstall(bytes calldata) public virtual {
        _unsafeSetDelay(msg.sender, 0, 0);
        _unsafeSetExpiration(msg.sender, 0, 0);
    }

    /**
     * @dev Allows an account to update its execution delay (see {getDelay}).
     *
     * The new delay will take effect after a transition period defined by the current delay
     * or minimum delay, whichever is longer. This prevents immediate security downgrades.
     * Can only be called by the account itself.
     */
    function setDelay(uint32 newDelay) public virtual {
        _setDelay(msg.sender, newDelay);
    }

    /**
     * @dev Allows an account to update its execution expiration (see {getExpiration}).
     *
     * The new expiration will take effect after a transition period defined by the current expiration
     * or minimum delay, whichever is longer. This prevents immediate security downgrades.
     * Can only be called by the account itself.
     */
    function setExpiration(uint32 newExpiration) public virtual {
        _setExpiration(msg.sender, newExpiration);
    }

    /**
     * @dev Schedules an operation to be executed after the account's delay period (see {getDelay}).
     * Operations are uniquely identified by the combination of `mode`, `executionCalldata`, and `salt`.
     * Can only be called by the account itself to schedule its own operations. See {_schedule}.
     */
    function schedule(Mode mode, bytes calldata executionCalldata, bytes32 salt) public virtual {
        _schedule(msg.sender, mode, executionCalldata, salt);
    }

    /**
     * @dev Cancels a previously scheduled operation. Can only be called by the account that
     * scheduled the operation. See {_cancel}.
     */
    function cancel(Mode mode, bytes calldata executionCalldata, bytes32 salt) public virtual {
        _cancel(msg.sender, mode, executionCalldata, salt);
    }

    /**
     * @dev Internal implementation for setting an account's delay. See {getDelay}.
     *
     * Emits an {ERC7579ExecutorDelayUpdated} event.
     *
     * NOTE: The delay is set to `type(uint32).max` if the new delay is `0`. This is a
     * reserved value to indicate that the module is not installed.
     */
    function _setDelay(address account, uint32 newDelay) internal virtual {
        _unsafeSetDelay(
            account,
            uint32(Math.ternary(newDelay == 0, NO_DELAY, newDelay)), // Safe downcast since both arguments are uint32
            minimumDelay()
        );
    }

    /**
     * @dev Internal implementation for setting an account's expiration. See {getExpiration}.
     *
     * Emits an {ERC7579ExecutorExpirationUpdated} event.
     */
    function _setExpiration(address account, uint32 newExpiration) internal virtual {
        _unsafeSetExpiration(account, newExpiration, minimumExpiration());
    }

    /// @dev Version of {_setDelay} without `type(uint32).max` check and with a custom minimum setback.
    function _unsafeSetDelay(address account, uint32 newDelay, uint32 minSetback) internal virtual {
        (uint32 delay, uint32 pendingDelay, uint48 effectTime) = getDelay(account);
        uint48 effect;
        (_config[account].delay, effect) = Time.pack(delay, pendingDelay, effectTime).withUpdate(newDelay, minSetback);
        emit ERC7579ExecutorDelayUpdated(account, newDelay, effect);
    }

    /// @dev Version of {_setExpiration} without `type(uint32).max` check and with a custom minimum setback.
    function _unsafeSetExpiration(address account, uint32 newExpiration, uint32 minSetback) internal virtual {
        (uint32 expiration, uint32 pendingExpiration, uint48 effectTime) = getExpiration(account);
        uint48 effect;
        (_config[account].expiration, effect) = Time.pack(expiration, pendingExpiration, effectTime).withUpdate(
            newExpiration,
            minSetback
        );
        emit ERC7579ExecutorExpirationUpdated(account, newExpiration, effect);
    }

    /**
     * @dev Internal version of {schedule} that takes an `account` address as an argument.
     *
     * Requirements:
     *
     * * Operation must not have been scheduled already. See {ERC7579ExecutorOperationAlreadyScheduled}.
     *
     * Emits an {ERC7579ExecutorOperationScheduled} event.
     */
    function _schedule(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) internal virtual returns (bytes32 operationId, Schedule memory schedule_) {
        bytes32 id = hashOperation(account, mode, executionCalldata, salt);
        (uint32 delay, , ) = getDelay(account);
        (uint32 expiration, , ) = getExpiration(account);

        uint48 timepoint = Time.timestamp() + delay;
        require(timepoint == 0, ERC7579ExecutorOperationAlreadyScheduled(id));

        _schedules[id].scheduledAt = timepoint;
        _schedules[id].delay = delay;
        _schedules[id].expiration = expiration;

        emit ERC7579ExecutorOperationScheduled(account, id, mode, executionCalldata, salt, timepoint);
        return (id, schedule_);
    }

    /**
     * @dev See {ERC7579Executor-_execute}.
     *
     * Requirements:
     *
     * * Operation must have been scheduled. Reverts with {ERC7579ExecutorOperationNotScheduled} otherwise.
     * * Operation must not have been executed yet. Reverts with {ERC7579ExecutorOperationAlreadyExecuted} otherwise.
     * * Operation must be ready for execution. Reverts with {ERC7579ExecutorOperationNotReady} otherwise.
     * * Operation must not have expired. Reverts with {ERC7579ExecutorOperationExpired} otherwise.
     *
     * NOTE: Anyone can trigger execution once the the execution delay has passed. See {getSchedule}.
     */
    function _execute(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) internal virtual override returns (bytes[] memory returnData) {
        bytes32 id = hashOperation(account, mode, executionCalldata, salt);
        (uint48 scheduledAt, uint48 executableAt, uint48 expiresAt, bool executed) = getSchedule(id);

        require(scheduledAt != 0, ERC7579ExecutorOperationNotScheduled(id));
        require(!executed, ERC7579ExecutorOperationAlreadyExecuted(id));
        require(Time.timestamp() >= executableAt, ERC7579ExecutorOperationNotReady(id, executableAt));
        require(Time.timestamp() < expiresAt, ERC7579ExecutorOperationExpired(id, expiresAt));

        _config[account].delay = EXECUTED.toDelay(); // Mark the operation as executed

        return super._execute(account, mode, executionCalldata, salt);
    }

    /**
     * @dev Internal version of {cancel} that takes an `account` address as an argument.
     *
     * [NOTE]
     * ====
     * Expired operations can be canceled, which allows for rescheduling. Consider
     * overriding this behavior in derived contracts if you want to prevent rescheduling
     * of expired operations.
     *
     * ```solidity
     * function _cancel(
     *     address account,
     *     Mode mode,
     *     bytes calldata executionCalldata,
     *     bytes32 salt
     * ) internal virtual override {
     *     bytes32 id = hashOperation(account, mode, executionCalldata, salt);
     *     (, , , uint48 expiresAt, ) = getSchedule(id);
     *     require(expiresAt == 0, ERC7579ExecutorOperationExpired(id, expiresAt));
     *     super._cancel(account, mode, executionCalldata, salt);
     * }
     * ```
     * ====
     *
     * Requirements:
     *
     * * Operation must have been scheduled. Reverts with {ERC7579ExecutorOperationNotScheduled} otherwise.
     * * Operation must not have been executed yet. Reverts with {ERC7579ExecutorOperationAlreadyExecuted} otherwise.
     *
     * Emits an {ERC7579ExecutorOperationCanceled} event.
     */
    function _cancel(address account, Mode mode, bytes calldata executionCalldata, bytes32 salt) internal virtual {
        bytes32 id = hashOperation(account, mode, executionCalldata, salt);
        (uint48 scheduledAt, , , bool executed) = getSchedule(id);

        require(scheduledAt != 0, ERC7579ExecutorOperationNotScheduled(id));
        require(!executed, ERC7579ExecutorOperationAlreadyExecuted(id));

        _schedules[id].scheduledAt = 0;
        _schedules[id].delay = 0;
        _schedules[id].expiration = 0;
        // _schedules[id].executed defaults to false
        emit ERC7579ExecutorOperationCanceled(account, id);
    }

    /// @dev Checks whether the module is uninstalled depending on the account's `delay` value.
    function _isDelayUninstalled(uint32 delay) private pure returns (bool) {
        return delay == 0;
    }
}
