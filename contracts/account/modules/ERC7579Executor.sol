// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC7579Module, MODULE_TYPE_EXECUTOR, IERC7579Execution} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Mode} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";

/**
 * @dev Basic implementation for ERC-7579 executor modules that provides execution functionality
 * for smart accounts.
 *
 * The module enables accounts to execute arbitrary operations, leveraging the execution
 * capabilities defined in the ERC-7579 standard. Developers can customize whether an operation
 * can be executed with custom rules by implementing the {_validateExecution} function in
 * derived contracts.
 *
 * TIP: This is a simplified executor that directly executes operations without delay or expiration
 * mechanisms. For a more advanced implementation with time-delayed execution patterns and
 * security features, see {ERC7579DelayedExecutor}.
 */
abstract contract ERC7579Executor is IERC7579Module {
    /// @dev Emitted when an operation is executed.
    event ERC7579ExecutorOperationExecuted(address indexed account, Mode mode, bytes callData, bytes32 salt);

    /// @dev Thrown when the execution is invalid. See {_validateExecution} for details.
    error ERC7579InvalidExecution();

    /// @inheritdoc IERC7579Module
    function isModuleType(uint256 moduleTypeId) public pure virtual returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR;
    }

    /**
     * @dev Check if the caller is authorized to execute operations.
     * Derived contracts can implement this with custom authorization logic.
     *
     * Example extension:
     *
     * ```solidity
     *  function _validateExecution(
     *     address account,
     *     Mode mode,
     *     bytes calldata executionCalldata,
     *     bytes32 salt
     *  ) internal view virtual returns (bool) {
     *    return isAuthorized; // custom logic to check authorization
     *  }
     *```
     */
    function _validateExecution(
        address account,
        Mode /* mode */,
        bytes calldata /* executionCalldata */,
        bytes32 /* salt */
    ) internal view virtual returns (bool);

    /**
     * @dev Executes an operation and returns the result data from the executed operation.
     * Restricted to the account itself by default. See {_execute} for requirements and
     * {_validateExecution} for authorization checks.
     */
    function execute(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) public virtual returns (bytes[] memory returnData) {
        bool allowed = _validateExecution(account, mode, executionCalldata, salt);
        returnData = _execute(account, mode, executionCalldata, salt); // Prioritize errors thrown in _execute
        require(allowed, ERC7579InvalidExecution());
        return returnData;
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
