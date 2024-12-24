// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC7579Hook, IERC7579ModuleConfig, MODULE_TYPE_HOOK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {ERC7579Utils, Mode} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {AccountERC7579} from "./AccountERC7579.sol";

abstract contract AccountERC7579Hooked is AccountERC7579 {
    address private _hook;

    modifier withHook() {
        address hook_ = hook();
        bool hooked = hook_ != address(0);
        bytes memory hookData;
        if (hooked) hookData = IERC7579Hook(hook_).preCheck(msg.sender, msg.value, msg.data);
        _;
        if (hooked) IERC7579Hook(hook_).postCheck(hookData);
    }

    function hook() public view returns (address) {
        return _hook;
    }

    function isModuleInstalled(
        uint256 moduleTypeId,
        address module,
        bytes calldata data
    ) public view override returns (bool) {
        return _isHookInstalled(module) || super.isModuleInstalled(moduleTypeId, module, data);
    }

    function _execute(Mode mode, bytes calldata executionCalldata) internal override withHook returns (bytes[] memory) {
        return super._execute(mode, executionCalldata);
    }

    function _installModule(uint256 moduleTypeId, address module, bytes memory initData) internal virtual override {
        _hook = module;
        super._installModule(moduleTypeId, module, initData);
    }

    function _uninstallModule(uint256 moduleTypeId, address module, bytes memory deInitData) internal virtual override {
        _hook = address(0);
        super._uninstallModule(moduleTypeId, module, deInitData);
    }

    function supportsModule(uint256 moduleTypeId) public view virtual override returns (bool) {
        return moduleTypeId == MODULE_TYPE_HOOK || super.supportsModule(moduleTypeId);
    }

    function _isHookInstalled(address module) internal view returns (bool) {
        return _hook == module;
    }

    function _fallback() internal virtual override withHook {
        super._fallback();
    }
}
