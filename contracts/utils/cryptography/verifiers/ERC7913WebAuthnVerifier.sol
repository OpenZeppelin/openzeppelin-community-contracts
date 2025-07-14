// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {WebAuthn} from "../WebAuthn.sol";
import {ERC7913P256Verifier} from "./ERC7913P256Verifier.sol";
import {IERC7913SignatureVerifier} from "@openzeppelin/contracts/interfaces/IERC7913.sol";

/**
 * @dev ERC-7913 signature verifier that supports WebAuthn authentication assertions.
 *
 * This verifier enables the validation of WebAuthn signatures using P256 public keys.
 * The key is expected to be a 64-byte concatenation of the P256 public key coordinates (qx || qy).
 * The signature is expected to be an abi-encoded {WebAuthn-WebAuthnAuth} struct.
 *
 * Uses {WebAuthn-verifyMinimal} for signature verification, which performs the essential
 * WebAuthn checks: type validation, challenge matching, and cryptographic signature verification.
 */
contract ERC7913WebAuthnVerifier is ERC7913P256Verifier {
    /// @inheritdoc ERC7913P256Verifier
    function verify(
        bytes calldata key,
        bytes32 hash,
        bytes calldata signature
    ) public view virtual override returns (bytes4) {
        // Signature length may be 0x40 or 0x41.
        if (key.length == 0x40 && signature.length >= 0x40) {
            bytes32 qx = bytes32(key[0x00:0x20]);
            bytes32 qy = bytes32(key[0x20:0x40]);
            if (WebAuthn.verifyMinimal(abi.encodePacked(hash), _toWebAuthnSignature(signature), qx, qy)) {
                return IERC7913SignatureVerifier.verify.selector;
            }
        }
        return super.verify(key, hash, signature);
    }

    /// @dev Non-reverting version of WebAuthn signature decoding.
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
