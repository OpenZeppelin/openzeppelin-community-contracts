// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC7579Module, MODULE_TYPE_EXECUTOR, IERC7579Execution} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {ERC7579Utils, Mode, CallType, ExecType, ModeSelector, ModePayload} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";

/**
 * @dev Base implementation for ERC-7579 executor modules that manages scheduling and executing
 * delayed operations. This module enables time-delayed execution patterns for smart accounts.
 *
 * Once scheduled (see {schedule}), operations can only be executed after their specified delay
 * period has elapsed (indicated during {onInstall}), creating a security window where suspicious
 * operations can be monitored and potentially canceled (see {cancel}) before execution (see {execute}).
 *
 * Accounts can customize their delay periods with {setDelay}, Delay changes take effect after a
 * transition period to prevent immediate security downgrades.
 *
 * IMPORTANT: This module assumes the {AccountERC7579} is the ultimate authority and does not restrict
 * module uninstallation. An account can bypass the time-delay security by simply uninstalling
 * the module. Consider adding safeguards in your Account implementation if uninstallation
 * protection is required for your security model.
 */
abstract contract ERC7579BaseExecutor is IERC7579Module {
    using Time for *;

    struct Schedule {
        uint48 scheduledAt;
        uint32 delay;
        bool executed;
    }

    mapping(address account => Time.Delay delay) private _accountDelays;
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

    /// @dev Emitted when an operation is executed.
    event ERC7579ExecutorOperationExecuted(address indexed account, bytes32 indexed operationId);

    /// @dev Emitted when a scheduled operation is canceled.
    event ERC7579ExecutorOperationCanceled(address indexed account, bytes32 indexed operationId);

    /// @dev Emitted when the execution delay is updated.
    event ERC7579ExecutorDelayUpdated(address indexed account, uint32 newDelay, uint48 effectTime);

    /// @dev Thrown when trying to execute an operation that is not scheduled.
    error ERC7579BaseExecutorOperationNotScheduled(bytes32 operationId);

    /// @dev Thrown when trying to execute an operation before its execution time.
    error ERC7579BaseExecutorOperationNotReady(bytes32 operationId, uint48 schedule);

    /// @dev Thrown when trying to schedule an operation that is already scheduled.
    error ERC7579BaseExecutorOperationAlreadyScheduled(bytes32 operationId);

    /// @dev Thrown when trying to execute an operation that has already been executed.
    error ERC7579BaseExecutorOperationAlreadyExecuted(bytes32 operationId);

    /// @inheritdoc IERC7579Module
    function isModuleType(uint256 moduleTypeId) public pure virtual returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR;
    }

    /**
     * @dev Sets up the module's initial configuration when installed by an account.
     * The account calling this function becomes registered with the module.
     *
     * The `initData` can contain an `abi.encode(uint32(initialDelay))` value.
     * The delay will be set to the maximum of this value and the minimum delay if provided.
     * Otherwise, the delay will be set to the minimum delay.
     */
    function onInstall(bytes calldata initData) public virtual {
        uint32 minDelay = minimumDelay(); // Up to ~136 years.
        uint32 delay = initData.length > 0
            ? uint32(Math.max(minDelay, abi.decode(initData, (uint32)))) // Safe downcast since both arguments are uint32
            : minDelay;
        _accountDelays[msg.sender] = delay.toDelay();
    }

    /**
     * @dev Cleans up account-specific state when the module is uninstalled from an account.
     *
     * IMPORTANT: This function does not clean up scheduled operations. This means operations
     * could potentially be re-executed if the module is reinstalled later. This is a deliberate
     * design choice, but module implementations may want to override this behavior to clear
     * scheduled operations during uninstallation for their specific use cases.
     */
    function onUninstall(bytes calldata) public virtual {
        address account = msg.sender;
        _accountDelays[account] = Time.toDelay(0);
    }

    /// @dev Minimum delay for operations. Default for accounts that do not set a custom delay.
    function minimumDelay() public view virtual returns (uint32) {
        return 1 days;
    }

    /// @dev Expiration time for operations. Defaults to `type(uint32).max` (no expiration).
    function expiration() public view virtual returns (uint32) {
        return type(uint32).max;
    }

    /// @dev Delay for a specific account. If not set, returns the minimum delay.
    function getDelay(
        address account
    ) public view virtual returns (uint32 delay, uint32 pendingDelay, uint48 effectTime) {
        (uint32 currentDelay, uint32 newDelay, uint48 effect) = _accountDelays[account].getFull();
        return (
            uint32(Math.max(currentDelay, minimumDelay())), // Safe downcast since both arguments are uint32
            newDelay,
            effect
        );
    }

    /**
     * @dev Schedule for an operation. Returns default values if not set
     * (i.e. `uint48(0)`, `uint32(0)`, `uint48(0)`, and `false`).
     */
    function getSchedule(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) public view virtual returns (uint48 scheduledAt, uint32 delay, uint48 timepoint, bool executed) {
        return getSchedule(hashOperation(account, mode, executionCalldata, salt));
    }

    /// @dev Same as {getSchedule} but with the operation id.
    function getSchedule(
        bytes32 operationId
    ) public view virtual returns (uint48 scheduledAt, uint32 delay, uint48 timepoint, bool executed) {
        Schedule storage schedule_ = _schedules[operationId];
        scheduledAt = schedule_.scheduledAt;
        delay = schedule_.delay;
        timepoint = scheduledAt + delay;
        return (scheduledAt, delay, timepoint, schedule_.executed);
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
     * @dev Allows an account to update its execution delay (see {getDelay}).
     *
     * The new delay will take effect after a transition period defined by the current delay
     * or minimum delay, whichever is longer. This prevents immediate security downgrades.
     * Can only be called by the account itself.
     */
    function setDelay(uint32 newDelay) public virtual {
        address account = msg.sender;
        _setDelay(account, newDelay);
    }

    /**
     * @dev Schedules an operation to be executed after the account's delay period (see {getDelay}).
     * Operations are uniquely identified by the combination of `mode`, `executionCalldata`, and `salt`.
     * Can only be called by the account itself to schedule its own operations.
     *
     * Requirements:
     *
     * * Operation must not have been scheduled already. Reverts with {ERC7579BaseExecutorOperationAlreadyScheduled} otherwise.
     */
    function schedule(Mode mode, bytes calldata executionCalldata, bytes32 salt) public virtual {
        _schedule(msg.sender, mode, executionCalldata, salt);
    }

    /**
     * @dev Executes a previously scheduled operation if its delay period has elapsed (see {getDelay}).
     * Returns the result data from the executed operation.
     *
     * Requirements:
     *
     * * Operation must have been scheduled. Reverts with {ERC7579BaseExecutorOperationNotScheduled} otherwise.
     * * Operation must not have been executed yet. Reverts with {ERC7579BaseExecutorOperationAlreadyExecuted} otherwise.
     * * Operation must be ready for execution. Reverts with {ERC7579BaseExecutorOperationNotReady} otherwise.
     *
     * The operation must be scheduled and not already executed.
     *
     * NOTE: Anyone can trigger execution once the timepoint has been reached.
     */
    function execute(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) public virtual returns (bytes[] memory returnData) {
        return _execute(account, mode, executionCalldata, salt);
    }

    /**
     * @dev Cancels a previously scheduled operation. Can only be called by the account that scheduled the operation.
     *
     * Requirements:
     *
     * * Operation must have been scheduled. Reverts with {ERC7579BaseExecutorOperationNotScheduled} otherwise.
     */
    function cancel(Mode mode, bytes calldata executionCalldata, bytes32 salt) public virtual {
        _cancel(msg.sender, mode, executionCalldata, salt);
    }

    /**
     * @dev Internal implementation for setting an account's delay.
     *
     * Updates the account's delay configuration and emits an event with the
     * new delay and when it will take effect.
     */
    function _setDelay(address account, uint32 newDelay) internal virtual {
        uint48 effect;
        (_accountDelays[account], effect) = _accountDelays[account].withUpdate(newDelay, minimumDelay());
        emit ERC7579ExecutorDelayUpdated(account, newDelay, effect);
    }

    /// @dev Internal version of {schedule} that takes an `account` address as an argument.
    function _schedule(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) internal virtual returns (bytes32 operationId, Schedule memory schedule_) {
        bytes32 id = hashOperation(account, mode, executionCalldata, salt);
        (uint32 delay, , ) = getDelay(account);

        uint48 timepoint = Time.timestamp() + delay;
        require(timepoint == 0, ERC7579BaseExecutorOperationAlreadyScheduled(id));

        schedule_ = Schedule(Time.timestamp(), delay, false);
        _schedules[id] = schedule_;

        emit ERC7579ExecutorOperationScheduled(account, id, mode, executionCalldata, salt, timepoint);
        return (id, schedule_);
    }

    /// @dev Internal version of {execute}.
    function _execute(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) internal virtual returns (bytes[] memory returnData) {
        bytes32 id = hashOperation(account, mode, executionCalldata, salt);
        (uint48 scheduledAt, , uint48 timepoint, bool executed) = getSchedule(id);

        require(scheduledAt != 0, ERC7579BaseExecutorOperationNotScheduled(id));
        require(!executed, ERC7579BaseExecutorOperationAlreadyExecuted(id));
        require(Time.timestamp() >= timepoint, ERC7579BaseExecutorOperationNotReady(id, timepoint));

        _schedules[id].executed = true; // Mark the operation as executed
        emit ERC7579ExecutorOperationExecuted(account, id);
        return IERC7579Execution(account).executeFromExecutor(Mode.unwrap(mode), executionCalldata);
    }

    /// @dev Internal version of {cancel} that takes an `account` address as an argument.
    function _cancel(address account, Mode mode, bytes calldata executionCalldata, bytes32 salt) public virtual {
        bytes32 id = hashOperation(account, mode, executionCalldata, salt);
        (uint48 scheduledAt, , , bool executed) = getSchedule(id);

        require(scheduledAt != 0, ERC7579BaseExecutorOperationNotScheduled(id));
        require(!executed, ERC7579BaseExecutorOperationAlreadyExecuted(id));

        _schedules[id].scheduledAt = 0;
        _schedules[id].delay = 0;
        _schedules[id].executed = false;
        emit ERC7579ExecutorOperationCanceled(account, id);
    }
}
