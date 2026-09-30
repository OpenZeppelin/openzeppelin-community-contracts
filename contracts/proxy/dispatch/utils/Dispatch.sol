// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Dispatch
 * @dev TODO
 */
library Dispatch {
    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Dispatch.VMT")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _DISPATCH_VMT_SLOT = 0xe6b1591f932b472559c00c679d5b3da28bf0ed2fd643b2ef77392cbec1743c00;

    struct VMT {
        address _owner;
        mapping(bytes4 => address) _vtable;
    }

    /**
     * @dev Get singleton instance
     */
    function instance() internal pure returns (VMT storage store) {
        bytes32 position = _DISPATCH_VMT_SLOT;
        assembly {
            store.slot := position
        }
    }

    /**
     * @dev Ownership management
     */
    function getOwner(VMT storage store) internal view returns (address) {
        return store._owner;
    }

    function setOwner(VMT storage store, address newOwner) internal {
        emit Ownable.OwnershipTransferred(store._owner, newOwner);
        store._owner = newOwner;
    }

    function enforceOwner(VMT storage store, address account) internal view {
        require(getOwner(store) == account, Ownable.OwnableUnauthorizedAccount(account));
    }

    /**
     * @dev Delegation management
     */
    event VMTUpdate(bytes4 indexed selector, address oldImplementation, address newImplementation);

    function getFunction(VMT storage store, bytes4 selector) internal view returns (address) {
        return store._vtable[selector];
    }

    function setFunction(VMT storage store, bytes4 selector, address module) internal {
        emit VMTUpdate(selector, store._vtable[selector], module);
        store._vtable[selector] = module;
    }
}
