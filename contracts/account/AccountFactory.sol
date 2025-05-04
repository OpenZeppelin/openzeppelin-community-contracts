// contracts/MyFactoryAccount.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @dev A factory contract to create smart accounts on demand.
 *
 * This factory takes an opinionated approach of using initializable
 * https://docs.openzeppelin.com/contracts/5.x/api/proxy#Clones[clones]. However,
 * it is possible to create account factories that don't require initialization
 * or use other deployment patterns.
 *
 * See {predictAddress} and {cloneAndInitialize} for details on how to create accounts.
 */
contract AccountFactory {
    using Clones for address;
    using Address for address;

    address private immutable _impl;

    /// @dev Sets the implementation contract address to be used for cloning accounts.
    constructor(address impl_) {
        _impl = impl_;
    }

    /// @dev Predict the address of the account
    function predictAddress(bytes32 salt, bytes calldata callData) public view virtual returns (address, bytes32) {
        bytes32 calldataSalt = _saltedCallData(salt, callData);
        return (_impl.predictDeterministicAddress(calldataSalt, address(this)), calldataSalt);
    }

    /**
     * @dev Create clone accounts on demand and return the address. Uses `callData` to initialize the clone.
     *
     * NOTE: The function will not revert if the predicted address already exists. Instead, it will return the existing address.
     */
    function cloneAndInitialize(bytes32 salt, bytes calldata callData) public virtual returns (address) {
        return _cloneAndInitialize(salt, callData);
    }

    /// @dev Same as {cloneAndInitialize}, but internal.
    function _cloneAndInitialize(bytes32 salt, bytes calldata callData) internal virtual returns (address) {
        (address predicted, bytes32 _calldataSalt) = predictAddress(salt, callData);
        if (predicted.code.length == 0) {
            _impl.cloneDeterministic(_calldataSalt);
            predicted.functionCall(callData);
        }
        return predicted;
    }

    /// @dev Creates a unique that includes the initialization arguments (i.e. `callData`) as part of the salt.
    function _saltedCallData(bytes32 salt, bytes calldata callData) internal pure virtual returns (bytes32) {
        // Scope salt to the callData to avoid front-running the salt with a different callData
        return keccak256(abi.encodePacked(salt, callData));
    }
}
