// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {AbstractSigner} from "./AbstractSigner.sol";

/**
 * @dev Implementation of {AbstractSigner} using {ECDSA} signatures.
 *
 * An {_initializeSigner} function is provided to set the account's signer address. Doing so it's
 * easier for a factory, whose likely to use initializable clones of this contract.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyAccountECDSA is Account, SignerECDSA {
 *     constructor() EIP712("MyAccountECDSA", "1") {}
 *
 *     function initializeSigner(address signerAddr) public virtual initializer {
 *       // Will revert if the signer is already initialized
 *       _initializeSigner(signerAddr);
 *     }
 * }
 * ```
 *
 * IMPORTANT: Avoiding to call {_initializeSigner} either during construction (if used standalone)
 * or during initialization (if used as a clone) may leave the account either front-runnable or unusable.
 */
abstract contract SignerECDSA is AbstractSigner {
    /**
     * @dev The {signer} is already initialized.
     */
    error AccountECDSAUninitializedSigner(address signer);

    address private _signer;

    /**
     * @dev Initializes the account with the address of the native signer. This function can be called only once.
     */
    function _initializeSigner(address signerAddr) internal {
        if (_signer != address(0)) revert AccountECDSAUninitializedSigner(signerAddr);
        _signer = signerAddr;
    }

    /**
     * @dev Return the account's signer address.
     */
    function signer() public view virtual returns (address) {
        return _signer;
    }

    /**
     * @dev Validates the signature using the account's signer.
     */
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(hash, signature);
        return signer() == recovered && err == ECDSA.RecoverError.NoError;
    }
}
