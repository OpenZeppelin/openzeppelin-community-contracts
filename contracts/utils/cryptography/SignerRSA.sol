// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {RSA} from "@openzeppelin/contracts/utils/cryptography/RSA.sol";
import {AbstractSigner} from "./AbstractSigner.sol";

/**
 * @dev Implementation of {AbstractSigner} using
 * https://docs.openzeppelin.com/contracts/api/utils#RSA[RSA] signatures.
 *
 * For {Account} usage, an {_initializeSigner} function is provided to set the {signer} public key.
 * Doing so it's easier for a factory, whose likely to use initializable clones of this contract.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyAccountRSA is Account, SignerRSA {
 *     constructor() EIP712("MyAccountRSA", "1") {}
 *
 *     function initializeSigner(bytes memory e, bytes memory n) external {
 *       // Will revert if the signer is already initialized
 *       _initializeSigner(e, n);
 *     }
 * }
 * ```
 *
 * IMPORTANT: Avoiding to call {_initializeSigner} either during construction (if used standalone)
 * or during initialization (if used as a clone) may leave the signer either front-runnable or unusable.
 */
abstract contract SignerRSA is AbstractSigner {
    /**
     * @dev The {signer} is already initialized.
     */
    error SignerRSAUninitializedSigner(bytes e, bytes n);

    bytes private _e;
    bytes private _n;

    /**
     * @dev Initializes the signer with the RSA public key. This function can be called only once.
     */
    function _initializeSigner(bytes memory e, bytes memory n) internal {
        if (_e.length != 0 || _n.length != 0) revert SignerRSAUninitializedSigner(e, n);
        _e = e;
        _n = n;
    }

    /**
     * @dev Return the signer's RSA public key.
     */
    function signer() public view virtual returns (bytes memory e, bytes memory n) {
        return (_e, _n);
    }

    /// @inheritdoc AbstractSigner
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        (bytes memory e, bytes memory n) = signer();
        return RSA.pkcs1Sha256(abi.encodePacked(hash), signature, e, n);
    }
}
