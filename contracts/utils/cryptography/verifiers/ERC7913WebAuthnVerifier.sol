// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {WebAuthn} from "../WebAuthn.sol";
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
 *
 * NOTE: Wallets that may require default P256 validation may install a P256 verifier separately.
 */
contract ERC7913WebAuthnVerifier is IERC7913SignatureVerifier {
    /// @inheritdoc IERC7913SignatureVerifier
    function verify(bytes calldata key, bytes32 hash, bytes calldata signature) public view virtual returns (bytes4) {
        // Signature length may be 0x40 or 0x41.
        if (key.length == 0x40 && signature.length >= 0x40) {
            bytes32 qx = bytes32(key[0x00:0x20]);
            bytes32 qy = bytes32(key[0x20:0x40]);
            WebAuthn.WebAuthnAuth memory auth = abi.decode(signature, (WebAuthn.WebAuthnAuth));
            if (WebAuthn.verifyMinimal(abi.encodePacked(hash), auth, qx, qy)) {
                return IERC7913SignatureVerifier.verify.selector;
            }
        }
        return 0xFFFFFFFF;
    }
}
