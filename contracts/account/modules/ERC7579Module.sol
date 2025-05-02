// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC7579Module} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

/**
 * @dev Abstract contract for implementing ERC-7579 modules.
 *
 * This contract provides a basic implementation of the ERC-7579 module interface,
 * which allows for modules to be installed and uninstalled from an ERC-7579 account.
 *
 * Developers must specify the module type ID in the constructor and `implement the {onInstall} and {onUninstall} functions in derived contracts.
 *
 * Example usage:
 *
 * ```solidity
 * contract MyExecutorModule is ERC7579Module(MODULE_TYPE_EXECUTOR) {
 *     function onInstall(bytes calldata data) public override {
 *         // Install logic here
 *         ...
 *         super.onInstall(data);
 *     }
 *
 *     function onUninstall(bytes calldata data) public override {
 *         // Uninstall logic here
 *         ...
 *         super.onUninstall(data);
 *     }
 *
 * }
 * ```
 */
abstract contract ERC7579Module is IERC7579Module {
    uint256 private immutable _moduleTypeId;

    /// @dev Emitted when a module is installed on an account.
    event ModuleInstalledReceived(address account, bytes data);

    /// @dev Emitted when a module is uninstalled from an account.
    event ModuleUninstalledReceived(address account, bytes data);

    constructor(uint256 moduleTypeId) {
        _moduleTypeId = moduleTypeId;
    }

    /// @inheritdoc IERC7579Module
    function onInstall(bytes calldata data) public virtual {
        emit ModuleInstalledReceived(msg.sender, data);
    }

    /// @inheritdoc IERC7579Module
    function onUninstall(bytes calldata data) public virtual {
        emit ModuleUninstalledReceived(msg.sender, data);
    }

    /// @inheritdoc IERC7579Module
    function isModuleType(uint256 moduleTypeId) external view virtual returns (bool) {
        return moduleTypeId == _moduleTypeId;
    }
}
