// contracts/MyFactoryAccount.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {MyAccountECDSA} from "./MyAccountECDSA.sol";

/**
 * @dev A factory contract to create ECDSA accounts on demand.
 */
contract MyFactoryAccount {
    using Clones for address;

    address private immutable _impl = address(new MyAccountECDSA());

    /// @dev Predict the address of the account
    function predictAddress(bytes32 salt) public view returns (address) {
        return _impl.predictDeterministicAddress(salt, address(this));
    }

    /// @dev Create clone accounts on demand
    function cloneAndInitialize(bytes32 salt, address signer) public returns (address) {
        return _cloneAndInitialize(salt, signer);
    }

    /// @dev Create clone accounts on demand and return the address. Uses `signer` to initialize the clone.
    function _cloneAndInitialize(bytes32 salt, address signer) internal returns (address) {
        // Scope salt to the signer to avoid front-running the salt with a different signer
        bytes32 _signerSalt = keccak256(abi.encodePacked(salt, signer));

        address predicted = predictAddress(_signerSalt);
        if (predicted.code.length == 0) {
            _impl.cloneDeterministic(_signerSalt);
            MyAccountECDSA(payable(predicted)).initializeSigner(signer);
        }
        return predicted;
    }
}
