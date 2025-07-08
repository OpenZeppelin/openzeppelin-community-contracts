// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC7579Module, MODULE_TYPE_EXECUTOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {ERC7579Executor} from "./ERC7579Executor.sol";
import {ERC7579Utils} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @dev Implementation of an {ERC7579Executor} that allows authorizing specific function selectors
 * that can be executed on the account.
 *
 * This module provides a way to restrict which functions can be executed on the account by
 * maintaining a set of allowed function selectors. Only calls to functions with selectors
 * in the set will be allowed to execute.
 */
abstract contract ERC7579SelectorExecutor is ERC7579Executor {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @dev Emitted when a selector is added to the set
    event ERC7579ExecutorSelectorAuthorized(address indexed account, bytes4 selector);

    /// @dev Emitted when a selector is removed from the set
    event ERC7579ExecutorSelectorRemoved(address indexed account, bytes4 selector);

    /// @dev Error thrown when attempting to execute a non-authorized selector
    error ERC7579ExecutorSelectorNotAuthorized(bytes4 selector);

    /// @dev Mapping from account to set of authorized selectors
    mapping(address account => EnumerableSet.Bytes32Set) private _authorizedSelectors;

    ///  @dev Returns whether a selector is authorized for the specified account
    function isAuthorized(address account, bytes4 selector) public view virtual returns (bool) {
        return _authorizedSelectors[account].contains(selector);
    }

    /**
     * @dev Returns the set of authorized selectors for the specified account.
     *
     * WARNING: This operation copies the entire selectors set to memory, which
     * can be expensive or may result in unbounded computation.
     */
    function selectors(address account) public view virtual returns (bytes4[] memory) {
        bytes32[] memory bytes32Selectors = _authorizedSelectors[account].values();
        bytes4[] memory selectors_ = new bytes4[](bytes32Selectors.length);
        for (uint256 i = 0; i < bytes32Selectors.length; i++) {
            selectors_[i] = bytes4(bytes32Selectors[i]);
        }
        return selectors_;
    }

    /**
     * @dev Sets up the module's initial configuration when installed by an account.
     * The initData should be encoded as: `abi.encode(bytes4[] selectors)`
     */
    function onInstall(bytes calldata initData) public virtual override {
        if (initData.length > 0) {
            bytes4[] memory selectors_ = abi.decode(initData, (bytes4[]));
            _addSelectors(msg.sender, selectors_);
        }
    }

    /**
     * @dev Cleans up module's configuration when uninstalled from an account.
     * Clears all selectors.
     *
     * WARNING: This function has unbounded gas costs and may become uncallable if the set grows too large.
     * See {EnumerableSetExtended-clear}.
     */
    function onUninstall(bytes calldata /* data */) public virtual override {
        _authorizedSelectors[msg.sender].clear();
    }

    /// @dev Adds `selectors` to the set for the calling account
    function addSelectors(bytes4[] memory newSelectors) public virtual {
        _addSelectors(msg.sender, newSelectors);
    }

    /// @dev Removes a selector from the set for the calling account
    function removeSelectors(bytes4[] memory oldSelectors) public virtual {
        _removeSelectors(msg.sender, oldSelectors);
    }

    /// @dev Internal version of {addSelectors} that takes an `account` as argument
    function _addSelectors(address account, bytes4[] memory newSelectors) internal virtual {
        uint256 newSelectorsLength = newSelectors.length;
        for (uint256 i = 0; i < newSelectorsLength; i++) {
            if (_authorizedSelectors[account].add(newSelectors[i])) {
                emit ERC7579ExecutorSelectorAuthorized(account, newSelectors[i]);
            } // no-op if the selector is already in the set
        }
    }

    /// @dev Internal version of {removeSelectors} that takes an `account` as argument
    function _removeSelectors(address account, bytes4[] memory oldSelectors) internal virtual {
        uint256 oldSelectorsLength = oldSelectors.length;
        for (uint256 i = 0; i < oldSelectorsLength; i++) {
            if (_authorizedSelectors[account].remove(oldSelectors[i])) {
                emit ERC7579ExecutorSelectorRemoved(account, oldSelectors[i]);
            } // no-op if the selector is not in the set
        }
    }

    /**
     * @dev See {ERC7579Executor-_validateExecution}.
     * Validates that the selector (first 4 bytes of the actual callData) is authorized before execution.
     */
    function _validateExecution(
        address account,
        bytes32 /* salt */,
        bytes32 /* mode */,
        bytes calldata data
    ) internal virtual override returns (bytes calldata) {
        // Decode ERC7579 single execution calldata to extract the actual function callData
        (, , bytes calldata callData) = ERC7579Utils.decodeSingle(data);

        bytes4 selector = bytes4(callData[0:4]);
        require(isAuthorized(account, selector), ERC7579ExecutorSelectorNotAuthorized(selector));

        return data;
    }
}
