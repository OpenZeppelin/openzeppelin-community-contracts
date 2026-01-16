// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC165, IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC6900Module} from "../../../interfaces/IERC6900.sol";

abstract contract ERC6900ModuleMock is IERC6900Module, ERC165 {
    event ModuleInstalledReceived(address account, bytes data);
    event ModuleUninstalledReceived(address account, bytes data);

    constructor() {}

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC6900Module).interfaceId || super.supportsInterface(interfaceId);
    }

    function onInstall(bytes calldata data) public virtual {
        emit ModuleInstalledReceived(msg.sender, data);
    }

    function onUninstall(bytes calldata data) public virtual {
        emit ModuleUninstalledReceived(msg.sender, data);
    }

    function moduleId() public view virtual returns (string memory) {
        // vendor.module.semver
        return "@openzeppelin/community-contracts.ModuleERC6900.v0.0.0";
    }
}
