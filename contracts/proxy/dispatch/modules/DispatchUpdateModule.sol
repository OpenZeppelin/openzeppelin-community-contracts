// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Dispatch} from "../utils/Dispatch.sol";

/// @custom:stateless
contract DispatchUpdateModule is Context {
    using Dispatch for Dispatch.VMT;

    struct ModuleDefinition {
        address implementation;
        bytes4[] selectors;
    }

    /**
     * @dev Updates the vtable
     */
    function updateDispatchTable(ModuleDefinition[] calldata modules) public {
        Dispatch.VMT storage store = Dispatch.instance();

        store.enforceOwner(_msgSender());
        for (uint256 i = 0; i < modules.length; ++i) {
            ModuleDefinition memory module = modules[i];
            for (uint256 j = 0; j < module.selectors.length; ++j) {
                store.setFunction(module.selectors[j], module.implementation);
            }
        }
    }
}
