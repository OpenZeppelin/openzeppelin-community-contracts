// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {P256} from "@openzeppelin/contracts/utils/cryptography/P256.sol";

/**
 * @dev Library for verifying WebAuthn Authentication Assertions.
 *
 * WebAuthn enables strong authentication for smart contracts using secp256r1 public key cryptography
 * as an alternative to traditional secp256k1 ECDSA signatures. This library verifies signatures
 * generated during WebAuthn authentication ceremonies as specified in the
 * https://www.w3.org/TR/webauthn-2/[WebAuthn Level 2 standard].
 *
 * Inspired on:
 * - https://github.com/daimo-eth/p256-verifier/blob/master/src/WebAuthn.sol[daimo-eth implementation]
 * - https://github.com/base/webauthn-sol/blob/main/src/WebAuthn.sol[base implementation]
 */
library WebAuthn {
    struct WebAuthnAuth {
        /// @dev The WebAuthn authenticator data.
        /// https://www.w3.org/TR/webauthn-2/#dom-authenticatorassertionresponse-authenticatordata
        bytes authenticatorData;
        /// @dev The WebAuthn client data JSON.
        /// https://www.w3.org/TR/webauthn-2/#dom-authenticatorresponse-clientdatajson
        string clientDataJSON;
        /// @dev The index at which "challenge":"..." occurs in `clientDataJSON`.
        uint256 challengeIndex;
        /// @dev The index at which "type":"..." occurs in `clientDataJSON`.
        uint256 typeIndex;
        /// @dev The r value of secp256r1 signature
        uint256 r;
        /// @dev The s value of secp256r1 signature
        uint256 s;
    }

    /// @dev Bit 0 of the authenticator data flags: "User Present" bit.
    bytes1 private constant AUTH_DATA_FLAGS_UP = 0x01;
    /// @dev Bit 2 of the authenticator data flags: "User Verified" bit.
    bytes1 private constant AUTH_DATA_FLAGS_UV = 0x04;
    /// @dev Bit 3 of the authenticator data flags: "Backup Eligibility" bit.
    bytes1 private constant AUTH_DATA_FLAGS_BE = 0x08;
    /// @dev Bit 4 of the authenticator data flags: "Backup State" bit.
    bytes1 private constant AUTH_DATA_FLAGS_BS = 0x10;

    /// @dev The expected type string in the client data JSON when verifying assertion signatures.
    ///      https://www.w3.org/TR/webauthn-2/#dom-collectedclientdata-type
    // solhint-disable-next-line quotes
    bytes32 private constant EXPECTED_TYPE_HASH = keccak256('"type":"webauthn.get"');

    /**
     * @dev Verifies a WebAuthn Authentication Assertion as specified in the WebAuthn standard.
     * The function takes a `challenge` provided by the relying party, a flag indicating whether
     * user verification is required, a {WebAuthnAuth} struct containing authentication data,
     * and the `qx` and `qy` coordinates of the public key, returning true if the
     * https://www.w3.org/TR/webauthn-2/#sctn-verifying-assertion[authentication assertion] is valid.
     *
     * This implementation verifies:
     * - Type is "webauthn.get" (confirming this is an authentication, not registration)
     * - Challenge matches the expected value
     * - User Present (UP) bit is set
     * - User Verified (UV) bit is set (when requireUserVerification is true)
     * - Backup State (BS) and Backup Eligibility (BE) bits are valid (if BE=0, BS must also be 0)
     * - The cryptographic signature is valid for the given public key
     *
     * Unlike some implementations, this verifies the backup state bit relationship
     * as specified in the WebAuthn standard, which requires that if a credential
     * is backed up (BS=1), it must also be eligible for backup (BE=1).
     * Not enforcing this could allow security compromises if backups are not intended.
     *
     * For blockchain use cases, the following WebAuthn validations are omitted for valid reasons:
     *
     * * Origin validation: We don't verify the origin in clientDataJSON because in blockchain
     *   contexts, the origin is enforced by the authenticator and dapp frontend. High-quality
     *   authenticators (like iCloud Keychain, Google Password Manager) properly enforce this.
     * * RP ID hash validation: We don't verify that rpIdHash in authenticatorData matches the
     *   expected RP ID hash. This is typically enforced by platform-level protections (like
     *   Apple App Site Association, Google Asset Links). For additional security, consider
     *   including an expiry timestamp in signed data.
     * * Signature counter: We don't verify that the signature counter increases with each
     *   authentication. While this can help detect credential cloning, on-chain operations
     *   are frequently replay-protected by their nonce, making this check redundant.
     * * Extension outputs: We don't verify extension output values, as they're typically not
     *   critical for the core authentication security model in blockchain applications.
     * * Attestation: We don't verify attestation objects, as this implementation is designed
     *   for authentication (webauthn.get) rather than registration ceremonies.
     */
    function verify(
        bytes memory challenge,
        bool requireUserVerification,
        WebAuthnAuth memory auth,
        bytes32 qx,
        bytes32 qy
    ) internal view returns (bool) {
        // Verify authenticator data has sufficient length (37 bytes minimum):
        // - 32 bytes for rpIdHash
        // - 1 byte for flags
        // - 4 bytes for signature counter
        if (auth.authenticatorData.length < 37) {
            return false;
        }

        bytes1 flags = auth.authenticatorData[32];
        bytes memory clientDataJSON = bytes(auth.clientDataJSON);

        return
            validateExpectedTypeHash(clientDataJSON, auth.typeIndex) && // 11
            validateChallenge(clientDataJSON, auth.challengeIndex, challenge) && // 12
            validateUserPresentBitSet(flags) && // 16
            validateUserVerifiedBit(flags, requireUserVerification) && // 17
            validateBackupStateBit(flags) &&
            // Handles signature malleability internally
            P256.verify(
                sha256(
                    abi.encodePacked(
                        auth.authenticatorData,
                        sha256(clientDataJSON) // 19
                    )
                ),
                bytes32(auth.r),
                bytes32(auth.s),
                qx,
                qy
            ); // 20
    }

    /// @dev Validates that the https://www.w3.org/TR/webauthn-2/#up[User Present (UP)] bit is set.
    function validateUserPresentBitSet(bytes1 flags) internal pure returns (bool) {
        return (flags & AUTH_DATA_FLAGS_UP) == AUTH_DATA_FLAGS_UP;
    }

    /**
     * @dev Validates that the https://www.w3.org/TR/webauthn-2/#uv[User Verified (UV)] bit is set
     * if user verification
     */
    function validateUserVerifiedBit(bytes1 flags, bool requireUserVerification) internal pure returns (bool) {
        return !requireUserVerification || (flags & AUTH_DATA_FLAGS_UV) == AUTH_DATA_FLAGS_UV;
    }

    /**
     * @dev Validates that the https://www.w3.org/TR/webauthn-2/#be[Backup Eligibility (BE)] bit is set
     * if the https://www.w3.org/TR/webauthn-2/#bs[Backup State (BS)] bit is set.
     *
     * According to the WebAuthn spec, if a credential is backed up (BS=1), it must also be
     * eligible for backup (BE=1). This is a security requirement to prevent unauthorized
     * credential backup.
     *
     * The logic returns true if either:
     * - BE=1 (credential is eligible for backup), regardless of BS value
     * - BS=0 (credential is not backed up), regardless of BE value
     *
     * It only returns false when BE=0 and BS=1, which would indicate a credential
     * that's backed up but not eligible for backup - an invalid state.
     */
    function validateBackupStateBit(bytes1 flags) internal pure returns (bool) {
        return (flags & AUTH_DATA_FLAGS_BE) != 0 || (flags & AUTH_DATA_FLAGS_BS) == 0;
    }

    /**
     * @dev Validates that the https://www.w3.org/TR/webauthn-2/#type[Type] field in the client data JSON
     * is set to "webauthn.get".
     */
    function validateExpectedTypeHash(bytes memory clientDataJSON, uint256 typeIndex) internal pure returns (bool) {
        bytes memory typeValueBytes = Bytes.slice(clientDataJSON, typeIndex, typeIndex + 21);
        return keccak256(typeValueBytes) == EXPECTED_TYPE_HASH;
    }

    /// @dev Validates that the challenge in the client data JSON matches the `expectedChallenge`.
    function validateChallenge(
        bytes memory clientDataJSON,
        uint256 challengeIndex,
        bytes memory expectedChallenge
    ) internal pure returns (bool) {
        bytes memory expectedChallengeBytes = bytes(
            // solhint-disable-next-line quotes
            string.concat('"challenge":"', Base64.encodeURL(expectedChallenge), '"')
        );
        if (challengeIndex + expectedChallengeBytes.length > clientDataJSON.length) {
            return false;
        }

        bytes memory actualChallengeBytes = Bytes.slice(
            clientDataJSON,
            challengeIndex,
            challengeIndex + expectedChallengeBytes.length
        );

        return keccak256(actualChallengeBytes) == keccak256(expectedChallengeBytes);
    }
}
