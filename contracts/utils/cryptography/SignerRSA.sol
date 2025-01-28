// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {RSA} from "@openzeppelin/contracts/utils/cryptography/RSA.sol";
import {AbstractSigner} from "./AbstractSigner.sol";

/**
 * @dev Implementation of {AbstractSigner} using
 * https://docs.openzeppelin.com/contracts/api/utils#RSA[RSA] signatures.
 *
 * For {Account} usage, an {_setSigner} function is provided to set the {signer} public key.
 * Doing so it's easier for a factory, whose likely to use initializable clones of this contract.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyAccountRSA is Account, SignerRSA, Initializable {
 *     constructor() EIP712("MyAccountRSA", "1") {}
 *
 *     function initializeSigner(bytes memory e, bytes memory n) public initializer {
 *       _setSigner(e, n);
 *     }
 * }
 * ```
 *
 * IMPORTANT: Avoiding to call {_setSigner} either during construction (if used standalone)
 * or during initialization (if used as a clone) may leave the signer either front-runnable or unusable.
 */
abstract contract SignerRSA is AbstractSigner {
    bytes private _e;
    bytes private _n;

    /**
     * @dev Sets the signer with a RSA public key. This function should be called during construction
     * or through an initializater.
     */
    function _setSigner(bytes memory e, bytes memory n) internal {
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
