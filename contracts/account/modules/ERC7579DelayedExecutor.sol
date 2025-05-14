// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Mode} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {IERC7579ModuleConfig, MODULE_TYPE_EXECUTOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {ERC7579Executor} from "./ERC7579Executor.sol";

/**
 * @dev Extension of {ERC7579Executor} that allows scheduling and executing delayed operations
 * with expiration. This module enables time-delayed execution patterns for smart accounts.
 *
 * Once scheduled (see {schedule}), operations can only be executed after their specified delay
 * period has elapsed (indicated during {onInstall}), creating a security window where suspicious
 * operations can be monitored and potentially canceled (see {cancel}) before execution (see {execute}).
 *
 * Accounts can customize their delay periods with {setDelay}. Changes take effect after a transition
 * period to prevent immediate security downgrades. Operations have an expiration mechanism that
 * prevents them from being executed after a certain time has passed.
 *
 * IMPORTANT: This module assumes the {AccountERC7579} is the ultimate authority and does not restrict
 * module uninstallation. An account can bypass the time-delay security by simply uninstalling
 * the module. Consider adding safeguards in your Account implementation if uninstallation
 * protection is required for your security model.
 */
abstract contract ERC7579DelayedExecutor is ERC7579Executor {
    using Time for *;

    struct Schedule {
        // 1 slot = 48 + 32 + 32 + 1 + 1 = 114 bits ~ 14 bytes
        uint48 scheduledAt; // The time when the operation was scheduled
        uint32 executableAfter; // Time after the operation becomes executable
        uint32 expiresAfter; // Time after the operation expires
        bool executed;
        bool canceled;
    }

    struct ExecutionConfig {
        // 1 slot = 112 + 32 + 1 = 145 bits ~ 18 bytes
        Time.Delay delay;
        uint32 expiration; // Time after operation is OperationState.Ready to expire
        bool installed;
    }

    enum OperationState {
        Unknown,
        Scheduled,
        Ready,
        Expired,
        Executed,
        Canceled
    }

    /// @dev Emitted when a new operation is scheduled.
    event ERC7579ExecutorOperationScheduled(
        address indexed account,
        bytes32 indexed operationId,
        Mode mode,
        bytes executionCalldata,
        bytes32 salt,
        uint48 schedule
    );

    /// @dev Emitted when a new operation is canceled.
    event ERC7579ExecutorOperationCanceled(address indexed account, bytes32 indexed operationId);

    /// @dev Emitted when the execution delay is updated.
    event ERC7579ExecutorDelayUpdated(address indexed account, uint32 newDelay, uint48 effectTime);

    /// @dev Emitted when the expiration delay is updated.
    event ERC7579ExecutorExpirationUpdated(address indexed account, uint32 newExpiration);

    /**
     * @dev The current state of a operation is not the expected. The `expectedStates` is a bitmap with the
     * bits enabled for each OperationState enum position counting from right to left. See {_encodeStateBitmap}.
     *
     * NOTE: If `expectedState` is `bytes32(0)`, the operation is expected to not be in any state (i.e. not exist).
     */
    error ERC7579ExecutorUnexpectedOperationState(
        bytes32 operationId,
        OperationState currentState,
        bytes32 allowedStates
    );

    /// @dev The operation is not authorized to be canceled.
    error ERC7579ExecutorUnauthorizedCancellation();

    /// @dev The operation is not authorized to be scheduled.
    error ERC7579ExecutorUnauthorizedSchedule();

    mapping(address account => ExecutionConfig) private _config;
    mapping(bytes32 operationId => Schedule) private _schedules;

    /// @dev Current state of an operation.
    function state(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) public view returns (OperationState) {
        return state(hashOperation(account, mode, executionCalldata, salt));
    }

    /// @dev Same as {state}, but for a specific operation id.
    function state(bytes32 operationId) public view returns (OperationState) {
        if (_schedules[operationId].scheduledAt == 0) return OperationState.Unknown;
        if (_schedules[operationId].canceled) return OperationState.Canceled;
        if (_schedules[operationId].executed) return OperationState.Executed;
        (, uint48 executableAt, uint48 expiresAt) = getSchedule(operationId);
        if (block.timestamp < executableAt) return OperationState.Scheduled;
        if (block.timestamp > expiresAt) return OperationState.Expired;
        return OperationState.Ready;
    }

    /// @dev See {ERC7579Executor-canExecute}. Allows anyone to execute an operation if it's {OperationState-Ready}.
    function canExecute(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) public view virtual override returns (bool) {
        return
            state(account, mode, executionCalldata, salt) == OperationState.Ready ||
            super.canExecute(account, mode, executionCalldata, salt);
    }

    /**
     * @dev Whether the caller is authorized to cancel operations.
     * By default, this checks if the caller is the account itself. Derived contracts can
     * override this to implement custom authorization logic.
     *
     * Example extension:
     *
     * ```
     *  function canCancel(
     *     address account,
     *     Mode mode,
     *     bytes calldata executionCalldata,
     *     bytes32 salt
     *  ) public view virtual returns (bool) {
     *    bool isAuthorized = ...; // custom logic to check authorization
     *    return isAuthorized || super.canCancel(account, mode, executionCalldata, salt);
     *  }
     *```
     */
    function canCancel(
        address account,
        Mode /* mode */,
        bytes calldata /* executionCalldata */,
        bytes32 /* salt */
    ) public view virtual returns (bool) {
        return account == msg.sender;
    }

    /**
     * @dev Whether the caller is authorized to schedule operations.
     * By default, this checks if the caller is the account itself. Derived contracts can
     * override this to implement custom authorization logic.
     *
     * Example extension:
     *
     * ```
     *  function canSchedule(
     *     address account,
     *     Mode mode,
     *     bytes calldata executionCalldata,
     *     bytes32 salt
     *  ) public view virtual returns (bool) {
     *    bool isAuthorized = ...; // custom logic to check authorization
     *    return isAuthorized || super.canSchedule(account, mode, executionCalldata, salt);
     *  }
     *```
     */
    function canSchedule(
        address account,
        Mode /* mode */,
        bytes calldata /* executionCalldata */,
        bytes32 /* salt */
    ) public view virtual returns (bool) {
        return account == msg.sender;
    }

    /// @dev Minimum delay after which {setDelay} takes effect.
    function minSetback() public view virtual returns (uint32) {
        return 1 days; // Up to ~136 years
    }

    /// @dev Delay for a specific account.
    function getDelay(
        address account
    ) public view virtual returns (uint32 delay, uint32 pendingDelay, uint48 effectTime) {
        return _config[account].delay.getFull();
    }

    /// @dev Expiration delay for account operations.
    function getExpiration(address account) public view virtual returns (uint32 expiration) {
        return _config[account].expiration;
    }

    /// @dev Schedule for an operation. Returns default values if not set (i.e. `uint48(0)`, `uint48(0)`, `uint48(0)`).
    function getSchedule(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) public view virtual returns (uint48 scheduledAt, uint48 executableAt, uint48 expiresAt) {
        return getSchedule(hashOperation(account, mode, executionCalldata, salt));
    }

    /// @dev Same as {getSchedule} but with the operation id.
    function getSchedule(
        bytes32 operationId
    ) public view virtual returns (uint48 scheduledAt, uint48 executableAt, uint48 expiresAt) {
        scheduledAt = _schedules[operationId].scheduledAt;
        executableAt = scheduledAt + _schedules[operationId].executableAfter;
        return (scheduledAt, executableAt, executableAt + _schedules[operationId].expiresAfter);
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

    /// @dev Default delay for account operations. Set if not provided during {onInstall}.
    function defaultDelay() public view virtual returns (uint32) {
        return 5 days;
    }

    /// @dev Default expiration for account operations. Set if not provided during {onInstall}.
    function defaultExpiration() public view virtual returns (uint32) {
        return 60 days;
    }

    /**
     * @dev Sets up the module's initial configuration when installed by an account.
     * The account calling this function becomes registered with the module.
     *
     * The `initData` may be `abi.encode(uint32(initialDelay), uint32(initialExpiration))`.
     * The delay will be set to the maximum of this value and the minimum delay if provided.
     * Otherwise, the delay will be set to the minimum delay.
     *
     * Behaves as a no-op if the module is already installed.
     *
     * Requirements:
     *
     * * The account (i.e `msg.sender`) must implement the {IERC7579ModuleConfig} interface.
     * * `initData` must be empty or decode correctly to `(uint32, uint32)`.
     */
    function onInstall(bytes calldata initData) public virtual {
        if (!_config[msg.sender].installed) {
            _config[msg.sender].installed = true;
            (uint32 initialDelay, uint32 initialExpiration) = initData.length > 0
                ? abi.decode(initData, (uint32, uint32))
                : (defaultDelay(), defaultExpiration());
            // An old delay might be still present
            // So we set 0 for the minimum setback relying on any old value as the minimum delay
            _setDelay(msg.sender, initialDelay, 0);
            _setExpiration(msg.sender, initialExpiration);
        }
    }

    /**
     * @dev Allows an account to update its execution delay (see {getDelay}).
     *
     * The new delay will take effect after a transition period defined by the current delay
     * or {minSetback}, whichever is longer. This prevents immediate security downgrades.
     * Can only be called by the account itself.
     */
    function setDelay(uint32 newDelay) public virtual {
        _setDelay(msg.sender, newDelay, minSetback());
    }

    /// @dev Allows an account to update its execution expiration (see {getExpiration}).
    function setExpiration(uint32 newExpiration) public virtual {
        _setExpiration(msg.sender, newExpiration);
    }

    /**
     * @dev Schedules an operation to be executed after the account's delay period (see {getDelay}).
     * Operations are uniquely identified by the combination of `mode`, `executionCalldata`, and `salt`.
     * See {canSchedule} for authorization checks.
     */
    function schedule(address account, Mode mode, bytes calldata executionCalldata, bytes32 salt) public virtual {
        bool allowed = canSchedule(account, mode, executionCalldata, salt);
        _schedule(account, mode, executionCalldata, salt); // Prioritize errors thrown in _schedule
        require(allowed, ERC7579ExecutorUnauthorizedSchedule());
    }

    /**
     * @dev Cancels a previously scheduled operation. Can only be called by the account that
     * scheduled the operation. See {_cancel}.
     */
    function cancel(address account, Mode mode, bytes calldata executionCalldata, bytes32 salt) public virtual {
        bool allowed = canCancel(account, mode, executionCalldata, salt);
        _cancel(account, mode, executionCalldata, salt); // Prioritize errors thrown in _cancel
        require(allowed, ERC7579ExecutorUnauthorizedCancellation());
    }

    /**
     * @dev Cleans up the {getDelay} and {getExpiration} values by scheduling them to `0`
     * and respecting the previous delay and expiration values.
     *
     * IMPORTANT: This function does not clean up scheduled operations. This means operations
     * could potentially be re-executed if the module is reinstalled later. This is a deliberate
     * design choice for efficiency, but module implementations may want to override this behavior
     * to clear scheduled operations during uninstallation for their specific use cases.
     *
     * WARNING: The account's delay will be removed if the account calls this function, allowing
     * immediate scheduling of operations. As an account operator, make sure to uninstall to a
     * predefined path in your account that properly handles the side effects of uninstallation.
     * See {AccountERC7579-uninstallModule}.
     */
    function onUninstall(bytes calldata) public virtual {
        _config[msg.sender].installed = false;
        _setDelay(msg.sender, 0, minSetback()); // Avoids immediate downgrades
        _setExpiration(msg.sender, 0);
    }

    /**
     * @dev Internal implementation for setting an account's delay. See {getDelay}.
     *
     * Emits an {ERC7579ExecutorDelayUpdated} event.
     */
    function _setDelay(address account, uint32 newDelay, uint32 minimumSetback) internal virtual {
        uint48 effect;
        (_config[account].delay, effect) = _config[account].delay.withUpdate(newDelay, minimumSetback);
        emit ERC7579ExecutorDelayUpdated(account, newDelay, effect);
    }

    /**
     * @dev Internal implementation for setting an account's expiration. See {getExpiration}.
     *
     * Emits an {ERC7579ExecutorExpirationUpdated} event.
     */
    function _setExpiration(address account, uint32 newExpiration) internal virtual {
        // Safe downcast since both arguments are uint32
        _config[account].expiration = newExpiration;
        emit ERC7579ExecutorExpirationUpdated(account, newExpiration);
    }

    /**
     * @dev Internal version of {schedule} that takes an `account` address as an argument.
     *
     * Requirements:
     *
     * * The operation must be {OperationState-Unknown}.
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
        _validateStateBitmap(id, _encodeStateBitmap(OperationState.Unknown));

        (uint32 executableAfter, , ) = getDelay(account);

        uint48 timepoint = Time.timestamp();
        _schedules[id].scheduledAt = timepoint;
        _schedules[id].executableAfter = executableAfter;
        _schedules[id].expiresAfter = getExpiration(account);

        emit ERC7579ExecutorOperationScheduled(account, id, mode, executionCalldata, salt, timepoint);
        return (id, schedule_);
    }

    /**
     * @dev See {ERC7579Executor-_execute}.
     *
     * Requirements:
     *
     * * The operation must be {OperationState-Ready}.
     *
     * NOTE: Anyone can trigger execution once the operation is {OperationState-Ready}. See {canExecute}.
     */
    function _execute(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) internal virtual override returns (bytes[] memory returnData) {
        bytes32 id = hashOperation(account, mode, executionCalldata, salt);
        _validateStateBitmap(id, _encodeStateBitmap(OperationState.Ready));

        _schedules[id].executed = true;

        return super._execute(account, mode, executionCalldata, salt);
    }

    /**
     * @dev Internal version of {cancel} that takes an `account` address as an argument.
     *
     * Requirements:
     *
     * * The operation must be {OperationState-Scheduled} or {OperationState-Ready}.
     *
     * Canceled operations can't be rescheduled. Emits an {ERC7579ExecutorOperationCanceled} event.
     */
    function _cancel(address account, Mode mode, bytes calldata executionCalldata, bytes32 salt) internal virtual {
        bytes32 id = hashOperation(account, mode, executionCalldata, salt);
        bytes32 allowedStates = _encodeStateBitmap(OperationState.Scheduled) | _encodeStateBitmap(OperationState.Ready);
        _validateStateBitmap(id, allowedStates);

        _schedules[id].canceled = true;

        emit ERC7579ExecutorOperationCanceled(account, id);
    }

    /**
     * @dev Check that the current state of a operation matches the requirements described by the `allowedStates` bitmap.
     * This bitmap should be built using {_encodeStateBitmap}.
     *
     * If requirements are not met, reverts with a {ERC7579ExecutorUnexpectedOperationState} error.
     */
    function _validateStateBitmap(bytes32 operationId, bytes32 allowedStates) internal view returns (OperationState) {
        OperationState currentState = state(operationId);
        require(
            _encodeStateBitmap(currentState) & allowedStates != bytes32(0),
            ERC7579ExecutorUnexpectedOperationState(operationId, currentState, allowedStates)
        );
        return currentState;
    }

    /**
     * @dev Encodes a `OperationState` into a `bytes32` representation where each bit enabled corresponds to
     * the underlying position in the `OperationState` enum. For example:
     *
     * 0x000...10000
     *   ^^^^^^------ ...
     *         ^----- Canceled
     *          ^---- Executed
     *           ^--- Ready
     *            ^-- Scheduled
     *             ^- Unknown
     */
    function _encodeStateBitmap(OperationState operationState) internal pure returns (bytes32) {
        return bytes32(1 << uint8(operationState));
    }
}
