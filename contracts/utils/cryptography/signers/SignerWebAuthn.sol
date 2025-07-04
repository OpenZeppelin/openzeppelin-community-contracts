// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SignerP256} from "./SignerP256.sol";
import {WebAuthn} from "../WebAuthn.sol";

/**
 * @dev Implementation of {SignerP256} that supports WebAuthn authentication assertions.
 *
 * This contract enables signature validation using WebAuthn authentication assertions,
 * leveraging the P256 public key stored in the contract. It allows for both WebAuthn
 * and raw P256 signature validation, providing compatibility with both signature types.
 *
 * The signature is expected to be an abi-encoded {WebAuthn-WebAuthnAuth} struct.
 *
 * Example usage:
 *
 * ```solidity
 * contract MyAccountWebAuthn is Account, SignerWebAuthn, Initializable {
 *     function initialize(bytes32 qx, bytes32 qy) public initializer {
 *         _setSigner(qx, qy);
 *     }
 * }
 * ```
 *
 * IMPORTANT: Failing to call {_setSigner} either during construction (if used standalone)
 * or during initialization (if used as a clone) may leave the signer either front-runnable or unusable.
 */
abstract contract SignerWebAuthn is SignerP256 {
    /**
     * @dev Validates a raw signature using the WebAuthn authentication assertion.
     *
     * In case the signature can't be validated, it falls back to the
     * {SignerP256-_rawSignatureValidation} method for raw P256 signature validation by passing
     * the raw `r` and `s` values from the signature.
     */
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        (bytes32 qx, bytes32 qy) = signer();

        return
            WebAuthn.verifyMinimal(abi.encodePacked(hash), _toWebAuthnSignature(signature), qx, qy) ||
            super._rawSignatureValidation(hash, signature);
    }

    /// @dev Non-reverting version of signature decoding.
    function _toWebAuthnSignature(bytes calldata signature) private pure returns (WebAuthn.WebAuthnAuth memory auth) {
        bool decodable;
        assembly ("memory-safe") {
            let offset := calldataload(signature.offset)
            // Validate the offset is within bounds and makes sense for a WebAuthnAuth struct
            // A valid offset should be 32 and point to data within the signature bounds
            decodable := and(eq(offset, 32), lt(add(offset, 0x80), signature.length))
        }
        return decodable ? abi.decode(signature, (WebAuthn.WebAuthnAuth)) : auth;
    }
}
