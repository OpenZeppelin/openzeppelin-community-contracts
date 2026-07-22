// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {Dispatch} from "../utils/Dispatch.sol";

/// @custom:stateless
contract DispatchOwnershipModule is Context {
    using Dispatch for Dispatch.VMT;

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        Dispatch.instance().enforceOwner(_msgSender());
        _;
    }

    /**
     * @dev Reads ownership for the vtable
     */
    function owner() public view virtual returns (address) {
        return Dispatch.instance().getOwner();
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        Dispatch.instance().setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), Ownable.OwnableInvalidOwner(newOwner));
        Dispatch.instance().setOwner(newOwner);
    }
}
