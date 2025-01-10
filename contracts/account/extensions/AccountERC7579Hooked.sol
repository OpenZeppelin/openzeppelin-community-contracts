// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC7579Hook, MODULE_TYPE_HOOK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Mode} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {AccountERC7579} from "./AccountERC7579.sol";

/**
 * @dev Extension of {AccountERC7579} with support for a single hook module (type 4).
 *
 * If installed, this extension will call the hook module's {IERC7579Hook-preCheck} before
 * executing any operation with {_execute} (including {execute} and {executeFromExecutor} by
 * default) and {IERC7579Hook-postCheck} thereafter.
 */
abstract contract AccountERC7579Hooked is AccountERC7579 {
    address private _hook;

    /**
     * @dev Calls {IERC7579Hook-preCheck} before executing the modified
     * function and {IERC7579Hook-postCheck} thereafter.
     */
    modifier withHook() {
        address hook_ = hook();
        bytes memory hookData;
        if (hook_ != address(0)) hookData = IERC7579Hook(hook_).preCheck(msg.sender, msg.value, msg.data);
        _;
        if (hook_ != address(0)) IERC7579Hook(hook_).postCheck(hookData);
    }

    /// @dev Returns the hook module address if installed, or `address(0)` otherwise.
    function hook() public view virtual returns (address) {
        return _hook;
    }

    /// @inheritdoc AccountERC7579
    function isModuleInstalled(
        uint256 moduleTypeId,
        address module,
        bytes calldata data
    ) public view virtual override returns (bool) {
        return _isHookInstalled(module) || super.isModuleInstalled(moduleTypeId, module, data);
    }

    /// @dev Hooked version of {AccountERC7579-_execute}.
    function _execute(
        Mode mode,
        bytes calldata executionCalldata
    ) internal virtual override withHook returns (bytes[] memory) {
        return super._execute(mode, executionCalldata);
    }

    /// @dev Installs a module with support for hook modules. See {AccountERC7579-_installModule}
    function _installModule(uint256 moduleTypeId, address module, bytes memory initData) internal virtual override {
        if (moduleTypeId == MODULE_TYPE_HOOK) _hook = module;
        super._installModule(moduleTypeId, module, initData);
    }

    /// @dev Uninstalls a module with support for hook modules. See {AccountERC7579-_uninstallModule}
    function _uninstallModule(uint256 moduleTypeId, address module, bytes memory deInitData) internal virtual override {
        if (moduleTypeId == MODULE_TYPE_HOOK) _hook = address(0);
        super._uninstallModule(moduleTypeId, module, deInitData);
    }

    /// @dev Supports hook modules. See {AccountERC7579-supportsModule}
    function supportsModule(uint256 moduleTypeId) public view virtual override returns (bool) {
        return moduleTypeId == MODULE_TYPE_HOOK || super.supportsModule(moduleTypeId);
    }

    /// @dev Returns whether a hook module is installed.
    function _isHookInstalled(address module) internal view virtual returns (bool) {
        return hook() == module;
    }
}
