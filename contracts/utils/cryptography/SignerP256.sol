// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {P256} from "@openzeppelin/contracts/utils/cryptography/P256.sol";
import {AbstractSigner} from "./AbstractSigner.sol";

/**
 * @dev Implementation of {AbstractSigner} using
 * https://docs.openzeppelin.com/contracts/api/utils#P256[P256] signatures.
 *
 * For {Account} usage, an {_initializeSigner} function is provided to set the {signer} public key.
 * Doing so it's easier for a factory, whose likely to use initializable clones of this contract.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyAccountP256 is Account, SignerP256 {
 *     constructor() EIP712("MyAccountP256", "1") {}
 *
 *     function initializeSigner(bytes32 qx, bytes32 qy) public virtual initializer {
 *       // Will revert if the signer is already initialized
 *       _initializeSigner(qx, qy);
 *     }
 * }
 * ```
 *
 * IMPORTANT: Avoiding to call {_initializeSigner} either during construction (if used standalone)
 * or during initialization (if used as a clone) may leave the signer either front-runnable or unusable.
 */
abstract contract SignerP256 is AbstractSigner {
    /**
     * @dev The {signer} is already initialized.
     */
    error SignerP256UninitializedSigner(bytes32 qx, bytes32 qy);

    bytes32 private _qx;
    bytes32 private _qy;

    /**
     * @dev Initializes the signer with the P256 public key. This function can be called only once.
     */
    function _initializeSigner(bytes32 qx, bytes32 qy) internal {
        if (_qx != 0 || _qy != 0) revert SignerP256UninitializedSigner(qx, qy);
        _qx = qx;
        _qy = qy;
    }

    /**
     * @dev Return the signer's P256 public key.
     */
    function signer() public view virtual returns (bytes32 qx, bytes32 qy) {
        return (_qx, _qy);
    }

    /// @inheritdoc AbstractSigner
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        if (signature.length < 0x40) return false;
        bytes32 r = bytes32(signature[0x00:0x20]);
        bytes32 s = bytes32(signature[0x20:0x40]);
        (bytes32 qx, bytes32 qy) = signer();
        return P256.verify(hash, r, s, qx, qy);
    }
}
