// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {P256} from "@openzeppelin/contracts/utils/cryptography/P256.sol";
import {AbstractSigner} from "./AbstractSigner.sol";

/**
 * @dev Implementation of {AbstractSigner} using
 * https://docs.openzeppelin.com/contracts/api/utils#P256[P256] signatures.
 *
 * For {Account} usage, an {_setSigner} function is provided to set the {signer} public key.
 * Doing so it's easier for a factory, whose likely to use initializable clones of this contract.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyAccountP256 is Account, SignerP256, Initializable {
 *     constructor() EIP712("MyAccountP256", "1") {}
 *
 *     function initializeSigner(bytes32 qx, bytes32 qy) public initializer {
 *       _setSigner(qx, qy);
 *     }
 * }
 * ```
 *
 * IMPORTANT: Avoiding to call {_setSigner} either during construction (if used standalone)
 * or during initialization (if used as a clone) may leave the signer either front-runnable or unusable.
 */
abstract contract SignerP256 is AbstractSigner {
    bytes32 private _qx;
    bytes32 private _qy;

    error SignerP256InvalidPublicKey(bytes32 qx, bytes32 qy);

    /**
     * @dev Sets the signer with a P256 public key. This function should be called during construction
     * or through an initializater.
     */
    function _setSigner(bytes32 qx, bytes32 qy) internal {
        if (!P256.isValidPublicKey(qx, qy)) revert SignerP256InvalidPublicKey(qx, qy);
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
