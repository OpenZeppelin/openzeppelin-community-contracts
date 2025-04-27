// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC7579Module, MODULE_TYPE_EXECUTOR, IERC7579Execution} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Mode} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";

/**
 * @dev Basic implementation for ERC-7579 executor modules that provides execution functionality
 * for smart accounts.
 *
 * The module enables accounts to execute arbitrary operations, leveraging the execution
 * capabilities defined in the ERC-7579 standard. Each execution emits an event for transparency
 * and auditability.
 *
 * TIP: This is a simplified executor that directly executes operations without delay or expiration
 * mechanisms. For a more advanced implementation with time-delayed execution patterns and
 * security features, see {ERC7579DelayedExecutor}.
 */
abstract contract ERC7579Executor is IERC7579Module {
    /// @dev Emitted when an operation is executed.
    event ERC7579ExecutorOperationExecuted(address indexed account, Mode mode, bytes callData, bytes32 salt);

    /// @inheritdoc IERC7579Module
    function isModuleType(uint256 moduleTypeId) public pure virtual returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR;
    }

    /**
     * @dev Executes an operation and returns the result data from the executed operation.
     * See {_execute} for requirements.
     */
    function execute(
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt
    ) public virtual returns (bytes[] memory returnData) {
        return _execute(msg.sender, mode, executionCalldata, salt);
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
