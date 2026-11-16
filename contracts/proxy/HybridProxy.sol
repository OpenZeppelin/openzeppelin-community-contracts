// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @dev A version of an ERC-1967 proxy that uses the address stored in the implementation slot as a beacon.
 *
 * The design allows to set an initial beacon that the contract may quit by upgrading to its own implementation
 * afterwards. Transition between the "beacon mode" and the "direct mode" require implementation that expose an
 * upgrade mechanism that writes to the ERC-1967 implementation slot. Note that UUPSUpgradable includes security
 * checks that are not compatible with this proxy design.
 *
 * WARNING: The fallback mechanism relies on the implementation not to define the {IBeacon-implementation} function.
 * Consider that if your implementation has this function, it'll be assumed as the beacon address, meaning that
 * the returned address will be used as this proxy's implementation.
 */
contract HybridProxy is Proxy {
    /**
     * @dev Initializes the proxy with an initial implementation. If data is present, it will be used to initialize the
     * implementation using a delegate call.
     */
    constructor(address implementation, bytes memory data) {
        ERC1967Utils.upgradeToAndCall(implementation, "");
        if (data.length > 0) {
            Address.functionDelegateCall(_implementation(), data);
        }
    }

    /**
     * @dev Returns the current implementation address according to ERC-1967's implementation slot.
     *
     * IMPORTANT: The way this function identifies whether the implementation is a beacon, is by checking
     * if it implements the {IBeacon-implementation} function. Consider that an actual implementation could
     * define this function, mistakenly identifying it as a beacon.
     */
    function _implementation() internal view override returns (address) {
        address implementation = ERC1967Utils.getImplementation();
        // A low-level call is used instead of try/catch because try/catch does not catch failures to decode the
        // return data. An implementation with a non-reverting fallback that returns less than 32 bytes would
        // otherwise make every call to the proxy revert.
        (bool success, bytes memory returndata) = implementation.staticcall(abi.encodeCall(IBeacon.implementation, ()));
        if (success && returndata.length >= 32) {
            uint256 result = abi.decode(returndata, (uint256));
            if (result <= type(uint160).max) return address(uint160(result));
        }
        return implementation;
    }
}
