// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {RSA} from "@openzeppelin/contracts/utils/cryptography/RSA.sol";
import {AccountCore} from "../draft-AccountCore.sol";

/**
 * @dev Account implementation using {RSA} signatures and {ERC7739Signer} for replay protection with
 * {ERC721Holder} and {ERC1155Holder} support.
 *
 * An {_initializeSigner} function is provided to set the account's signer address. Doing so it's
 * easier for a factory, whose likely to use initializable clones of this contract.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyAccountRSA is AccountRSA {
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
 * or during initialization (if used as a clone) may leave the account either front-runnable or unusable.
 */
abstract contract AccountRSA is AccountCore {
    /**
     * @dev The {signer} is already initialized.
     */
    error AccountRSAUninitializedSigner(bytes e, bytes n);

    bytes private _e;
    bytes private _n;

    /**
     * @dev Initializes the account with the RSA public key. This function can be called only once.
     */
    function _initializeSigner(bytes memory e, bytes memory n) internal {
        if (_e.length != 0 || _n.length != 0) revert AccountRSAUninitializedSigner(e, n);
        _e = e;
        _n = n;
    }

    /**
     * @dev Return the account's signer RSA public key.
     */
    function signer() public view virtual returns (bytes memory e, bytes memory n) {
        return (_e, _n);
    }

    /**
     * @dev Validates the signature using the account's signer.
     */
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        (bytes memory e, bytes memory n) = signer();
        return RSA.pkcs1Sha256(abi.encodePacked(hash), signature, e, n);
    }
}
