// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SignerP256} from "./SignerP256.sol";
import {WebAuthn} from "./WebAuthn.sol";
import {P256} from "@openzeppelin/contracts/utils/cryptography/P256.sol";

/**
 * @dev Implementation of {SignerP256} that supports WebAuthn authentication assertions.
 *
 * This contract enables signature validation using WebAuthn authentication assertions,
 * leveraging the P256 public key stored in the contract. It allows for both WebAuthn
 * and raw P256 signature validation, providing compatibility with both signature types.
 *
 * The signature is expected to be an abi-encoded {WebAuthn.WebAuthnAuth} struct.
 *
 * Example usage:
 *
 * ```solidity
 * contract MyAccountWebAuthN is Account, SignerWebAuthN, Initializable {
 *     constructor() EIP712("MyAccountWebAuthN", "1") {}
 *
 *     function initialize(bytes32 qx, bytes32 qy) public initializer {
 *         _setSigner(qx, qy);
 *     }
 * }
 * ```
 *
 * IMPORTANT: Failing to call {_setSigner} either during construction (if used standalone)
 * or during initialization (if used as a clone) may leave the signer either front-runnable or unusable.
 */
abstract contract SignerWebAuthN is SignerP256 {
    /**
     * @dev Validates a signature as a WebAuthn authentication assertion or as a raw P256 signature.
     *
     * If the signature is a valid abi-encoded {WebAuthn.WebAuthnAuth} struct, it is validated using
     * {WebAuthn.verifyMinimal}. Otherwise, it falls back to raw P256 signature validation using the
     * parent contract's implementation.
     *
     * @param hash The hash of the data that was signed (used as the WebAuthn challenge).
     * @param signature The signature bytes, expected to be an abi-encoded {WebAuthn.WebAuthnAuth} struct
     *                  or a raw P256 signature (r||s, 64 bytes).
     * @return True if the signature is valid according to WebAuthn or raw P256 validation, false otherwise.
     */
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        if (signature.length == 0) return false;
        (bytes32 qx, bytes32 qy) = signer();
        return
            WebAuthn.verifyMinimal(abi.encodePacked(hash), abi.decode(signature, (WebAuthn.WebAuthnAuth)), qx, qy) ||
            super._rawSignatureValidation(hash, signature[0x80:0xa0]);
    }
}
