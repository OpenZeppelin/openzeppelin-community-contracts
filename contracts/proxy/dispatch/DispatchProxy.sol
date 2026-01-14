// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {DispatchUpdateModule} from "./modules/DispatchUpdateModule.sol";
import {Dispatch} from "./utils/Dispatch.sol";

/**
 * @title DispatchProxy
 * @dev TODO
 */
contract DispatchProxy is Proxy {
    using Dispatch for Dispatch.VMT;

    bytes4 private constant _FALLBACK_SIG = 0xffffffff;

    error DispatchProxyMissingImplementation(bytes4 selector);

    constructor(address updateFacet, address initialOwner) {
        Dispatch.VMT storage store = Dispatch.instance();
        store.setOwner(initialOwner);
        store.setFunction(DispatchUpdateModule.updateDispatchTable.selector, updateFacet);
    }

    function _implementation() internal view virtual override returns (address module) {
        Dispatch.VMT storage store = Dispatch.instance();

        module = store.getFunction(msg.sig);
        if (module != address(0)) return module;

        module = store.getFunction(_FALLBACK_SIG);
        if (module != address(0)) return module;

        revert DispatchProxyMissingImplementation(msg.sig);
    }
}
