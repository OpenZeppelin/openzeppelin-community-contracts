// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IERC7579Module, MODULE_TYPE_EXECUTOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {ERC7579Executor} from "./ERC7579Executor.sol";
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
        return _selectors(account).contains(selector);
    }

    /**
     * @dev Returns the set of authorized selectors for the specified account.
     *
     * WARNING: This operation copies the entire selectors set to memory, which
     * can be expensive or may result in unbounded computation.
     */
    function selectors(address account) public view virtual returns (bytes4[] memory) {
        bytes32[] memory _selectors = _selectors(account).values();
        bytes4[] memory selectors = new bytes4[](_selectors.length);
        for (uint256 i = 0; i < _selectors.length; i++) {
            selectors[i] = bytes4(_selectors[i]);
        }
        return selectors;
    }

    /**
     * @dev Sets up the module's initial configuration when installed by an account.
     * The initData should be encoded as: `abi.encode(bytes4[] selectors)`
     */
    function onInstall(bytes calldata initData) public virtual override {
        if (initData.length > 0) {
            bytes4[] memory selectors = abi.decode(initData, (bytes4[]));
            _addSelectors(msg.sender, selectors);
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
        _selectors(msg.sender).clear();
    }

    /// @dev Adds `selectors` to the set for the calling account
    function addSelectors(bytes4[] memory selectors) public virtual {
        _addSelectors(msg.sender, selectors);
    }

    /// @dev Removes a selector from the set for the calling account
    function removeSelectors(bytes4[] memory selectors) public virtual {
        _removeSelectors(msg.sender, selectors);
    }

    /// @dev Returns the set of authorized selectors for the specified account.
    function _selectors(address account) internal view virtual returns (EnumerableSet.Bytes32Set storage) {
        return _authorizedSelectors[account];
    }

    /// @dev Internal version of {addSelectors} that takes an `account` as argument
    function _addSelectors(address account, bytes4[] memory selectors) internal virtual {
        uint256 selectorsLength = selectors.length;
        for (uint256 i = 0; i < selectorsLength; i++) {
            if (_selectors(account).add(selectors[i])) {
                emit ERC7579ExecutorSelectorAuthorized(account, selectors[i]);
            } // no-op if the selector is already in the set
        }
    }

    /// @dev Internal version of {removeSelectors} that takes an `account` as argument
    function _removeSelectors(address account, bytes4[] memory selectors) internal virtual {
        uint256 selectorsLength = selectors.length;
        for (uint256 i = 0; i < selectorsLength; i++) {
            if (_selectors(account).remove(selectors[i])) {
                emit ERC7579ExecutorSelectorRemoved(account, selectors[i]);
            } // no-op if the selector is not in the set
        }
    }

    /**
     * @dev See {ERC7579Executor-_validateExecution}.
     * Validates that the selector (first 4 bytes of `data`) is authorized before execution.
     */
    function _validateExecution(
        address account,
        bytes32 /* salt */,
        bytes32 /* mode */,
        bytes calldata data
    ) internal virtual override returns (bytes calldata) {
        bytes4 selector = bytes4(data[0:4]);
        require(isAuthorized(account, selector), ERC7579ExecutorSelectorNotAuthorized(selector));
        return data;
    }
}
