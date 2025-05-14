// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC7579Module, MODULE_TYPE_EXECUTOR, IERC7579Execution} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Mode} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";

/**
 * @dev Basic implementation for ERC-7579 executor modules that provides execution functionality
 * for smart accounts.
 *
 * The module enables accounts to execute arbitrary operations, leveraging the execution
 * capabilities defined in the ERC-7579 standard. By default, the executor is restricted to
 * operations initiated by the account itself, but this can be customized in derived contracts
 * by overriding the {canExecute} function.
 *
 * TIP: This is a simplified executor that directly executes operations without delay or expiration
 * mechanisms. For a more advanced implementation with time-delayed execution patterns and
 * security features, see {ERC7579DelayedExecutor}.
 */
abstract contract ERC7579Executor is IERC7579Module {
    /// @dev Emitted when an operation is executed.
    event ERC7579ExecutorOperationExecuted(address indexed account, Mode mode, bytes callData, bytes32 salt);

    /// @dev Thrown when the executor is uninstalled.
    error ERC7579UnauthorizedExecution();

    /// @inheritdoc IERC7579Module
    function isModuleType(uint256 moduleTypeId) public pure virtual returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR;
    }

    /**
     * @dev Check if the caller is authorized to execute operations.
     * By default, this checks if the caller is the account itself. Derived contracts can
     * override this to implement custom authorization logic.
     *
     * Example extension:
     *
     * ```solidity
     *  function canExecute(
     *     address account,
     *     Mode mode,
     *     bytes calldata executionCalldata,
     *     bytes32 salt
     *  ) public view virtual returns (bool) {
     *    bool isAuthorized = ...; // custom logic to check authorization
     *    return isAuthorized || super.canExecute(account, mode, executionCalldata, salt);
     *  }
     *```
     */
    function canExecute(
        address account,
        Mode /* mode */,
        bytes calldata /* executionCalldata */,
        bytes32 /* salt */
    ) public view virtual returns (bool) {
        return msg.sender == account;
    }

    /**
     * @dev Validates an execution request.
     *
     * Can be overridden by derived contracts to extend the default validation logic.
     */
    function _validateExecutionRequest(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) internal view virtual {
        require(canExecute(account, mode, executionCalldata, salt), ERC7579UnauthorizedExecution());
    }

    /**
     * @dev Executes an operation and returns the result data from the executed operation.
     * Restricted to the account itself by default. See {_execute} for requirements and
     * {canExecute} for authorization checks.
     */
    function execute(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) public virtual returns (bytes[] memory returnData) {
        _validateExecutionRequest(account, mode, executionCalldata, salt);
        return _execute(account, mode, executionCalldata, salt); // Prioritize errors thrown in _execute
    }

    /**
     * @dev Internal version of {execute}. Emits {ERC7579ExecutorOperationExecuted} event.
     *
     * Requirements:
     *
     * * The `account` must implement the {IERC7579Execution-executeFromExecutor} function.
     */
    function _execute(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) internal virtual returns (bytes[] memory returnData) {
        emit ERC7579ExecutorOperationExecuted(account, mode, executionCalldata, salt);
        return IERC7579Execution(account).executeFromExecutor(Mode.unwrap(mode), executionCalldata);
    }
}
