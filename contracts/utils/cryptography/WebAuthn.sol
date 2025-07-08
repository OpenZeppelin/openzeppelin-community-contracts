// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {P256} from "@openzeppelin/contracts/utils/cryptography/P256.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @dev Library for verifying WebAuthn Authentication Assertions.
 *
 * WebAuthn enables strong authentication for smart contracts using
 * https://docs.openzeppelin.com/contracts/5.x/api/utils#P256[P256]
 * as an alternative to traditional secp256k1 ECDSA signatures. This library verifies
 * signatures generated during WebAuthn authentication ceremonies as specified in the
 * https://www.w3.org/TR/webauthn-2/[WebAuthn Level 2 standard].
 *
 * For blockchain use cases, the following WebAuthn validations are intentionally omitted:
 *
 * * Origin validation: Origin verification in `clientDataJSON` is omitted as blockchain
 *   contexts rely on authenticator and dapp frontend enforcement. Standard authenticators
 *   implement proper origin validation.
 * * RP ID hash validation: Verification of `rpIdHash` in authenticatorData against expected
 *   RP ID hash is omitted. This is typically handled by platform-level security measures.
 *   Including an expiry timestamp in signed data is recommended for enhanced security.
 * * Signature counter: Verification of signature counter increments is omitted. While
 *   useful for detecting credential cloning, on-chain operations typically include nonce
 *   protection, making this check redundant.
 * * Extension outputs: Extension output value verification is omitted as these are not
 *   essential for core authentication security in blockchain applications.
 * * Attestation: Attestation object verification is omitted as this implementation
 *   focuses on authentication (`webauthn.get`) rather than registration ceremonies.
 *
 * Inspired by:
 *
 * * https://github.com/daimo-eth/p256-verifier/blob/master/src/WebAuthn.sol[daimo-eth implementation]
 * * https://github.com/base/webauthn-sol/blob/main/src/WebAuthn.sol[base implementation]
 */
library WebAuthn {
    struct WebAuthnAuth {
        bytes32 r; /// The r value of secp256r1 signature
        bytes32 s; /// The s value of secp256r1 signature
        uint256 challengeIndex; /// The index at which "challenge":"..." occurs in `clientDataJSON`.
        uint256 typeIndex; /// The index at which "type":"..." occurs in `clientDataJSON`.
        /// The WebAuthn authenticator data.
        /// https://www.w3.org/TR/webauthn-2/#dom-authenticatorassertionresponse-authenticatordata
        bytes authenticatorData;
        /// The WebAuthn client data JSON.
        /// https://www.w3.org/TR/webauthn-2/#dom-authenticatorresponse-clientdatajson
        string clientDataJSON;
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
    /// https://www.w3.org/TR/webauthn-2/#dom-collectedclientdata-type
    // solhint-disable-next-line quotes
    bytes32 private constant EXPECTED_TYPE_HASH = keccak256('"type":"webauthn.get"');

    /**
     * @dev Performs the absolute minimal verification of a WebAuthn Authentication Assertion.
     * This function includes only the essential checks required for basic WebAuthn security:
     *
     * 1. Type is "webauthn.get" (see {validateExpectedTypeHash})
     * 2. Challenge matches the expected value (see {validateChallenge})
     * 3. Cryptographic signature is valid for the given public key
     *
     * For most applications, use {verify} or {verifyStrict} instead.
     *
     * NOTE: This function intentionally omits User Presence (UP), User Verification (UV),
     * and Backup State/Eligibility checks. Use this only when broader compatibility with
     * authenticators is required or in constrained environments.
     */
    function verifyMinimal(
        bytes memory challenge,
        WebAuthnAuth memory auth,
        bytes32 qx,
        bytes32 qy
    ) internal view returns (bool) {
        // Verify authenticator data has sufficient length (37 bytes minimum):
        // - 32 bytes for rpIdHash
        // - 1 byte for flags
        // - 4 bytes for signature counter
        if (auth.authenticatorData.length < 37) return false;
        bytes memory clientDataJSON = bytes(auth.clientDataJSON);

        return
            validateExpectedTypeHash(clientDataJSON, auth.typeIndex) && // 11
            validateChallenge(clientDataJSON, auth.challengeIndex, challenge) && // 12
            // Handles signature malleability internally
            P256.verify(
                sha256(
                    abi.encodePacked(
                        auth.authenticatorData,
                        sha256(clientDataJSON) // 19
                    )
                ),
                auth.r,
                auth.s,
                qx,
                qy
            ); // 20
    }

    /**
     * @dev Performs standard verification of a WebAuthn Authentication Assertion.
     *
     * Same as {verifyMinimal}, but also verifies:
     *
     * [start=4]
     * 4. {validateUserPresentBitSet} - confirming physical user presence during authentication
     *
     * This compliance level satisfies the core WebAuthn verification requirements while
     * maintaining broad compatibility with authenticators. For higher security requirements,
     * consider using {verifyStrict}.
     */
    function verify(
        bytes memory challenge,
        WebAuthnAuth memory auth,
        bytes32 qx,
        bytes32 qy
    ) internal view returns (bool) {
        // 16 && rest
        return validateUserPresentBitSet(auth.authenticatorData[32]) && verifyMinimal(challenge, auth, qx, qy);
    }

    /**
     * @dev Performs strict verification of a WebAuthn Authentication Assertion.
     *
     * Same as {verify}, but also also verifies:
     *
     * [start=5]
     * 5. {validateUserVerifiedBitSet} - confirming stronger user authentication (biometrics/PIN)
     * 6. {validateBackupEligibilityAndState}- Backup Eligibility (`BE`) and Backup State (BS) bits
     * relationship is valid
     *
     * This strict verification is recommended for:
     *
     * * High-value transactions
     * * Privileged operations
     * * Account recovery or critical settings changes
     * * Applications where security takes precedence over broad authenticator compatibility
     */
    function verifyStrict(
        bytes memory challenge,
        WebAuthnAuth memory auth,
        bytes32 qx,
        bytes32 qy
    ) internal view returns (bool) {
        return
            validateUserVerifiedBitSet(auth.authenticatorData[32]) && // 17
            validateBackupEligibilityAndState(auth.authenticatorData[32]) && // Consistency check
            verify(challenge, auth, qx, qy);
    }

    /**
     * @dev Validates that the https://www.w3.org/TR/webauthn-2/#up[User Present (UP)] bit is set.
     * Step 16 in https://www.w3.org/TR/webauthn-2/#sctn-verifying-assertion[verifying an assertion].
     *
     * NOTE: Required by WebAuthn spec but may be skipped for platform authenticators
     * (Touch ID, Windows Hello) in controlled environments. Enforce for public-facing apps.
     */
    function validateUserPresentBitSet(bytes1 flags) internal pure returns (bool) {
        return (flags & AUTH_DATA_FLAGS_UP) == AUTH_DATA_FLAGS_UP;
    }

    /**
     * @dev Validates that the https://www.w3.org/TR/webauthn-2/#uv[User Verified (UV)] bit is set.
     * Step 17 in https://www.w3.org/TR/webauthn-2/#sctn-verifying-assertion[verifying an assertion].
     *
     * The UV bit indicates whether the user was verified using a stronger identification method
     * (biometrics, PIN, password). While optional, requiring UV=1 is recommended for:
     *
     * * High-value transactions and sensitive operations
     * * Account recovery and critical settings changes
     * * Privileged operations
     *
     * NOTE: For routine operations or when using hardware authenticators without verification capabilities,
     * `UV=0` may be acceptable. The choice of whether to require UV represents a security vs. usability
     * tradeoff - for blockchain applications handling valuable assets, requiring UV is generally safer.
     */
    function validateUserVerifiedBitSet(bytes1 flags) internal pure returns (bool) {
        return (flags & AUTH_DATA_FLAGS_UV) == AUTH_DATA_FLAGS_UV;
    }

    /**
     * @dev Validates the relationship between Backup Eligibility (`BE`) and Backup State (`BS`) bits
     * according to the WebAuthn specification.
     *
     * The function enforces that if a credential is backed up (`BS=1`), it must also be eligible
     * for backup (`BE=1`). This prevents unauthorized credential backup and ensures compliance
     * with the WebAuthn spec.
     *
     * Returns true in these valid states:
     *
     * * `BE=1`, `BS=0`: Credential is eligible but not backed up
     * * `BE=1`, `BS=1`: Credential is eligible and backed up
     * * `BE=0`, `BS=0`: Credential is not eligible and not backed up
     *
     * Returns false only when `BE=0` and `BS=1`, which is an invalid state indicating
     * a credential that's backed up but not eligible for backup.
     *
     * NOTE: While the WebAuthn spec defines this relationship between `BE` and `BS` bits,
     * validating it is not explicitly required as part of the core verification procedure.
     * Some implementations may choose to skip this check for broader authenticator
     * compatibility or when the application's threat model doesn't consider credential
     * syncing a major risk.
     */
    function validateBackupEligibilityAndState(bytes1 flags) internal pure returns (bool) {
        return (flags & AUTH_DATA_FLAGS_BE) != 0 || (flags & AUTH_DATA_FLAGS_BS) == 0;
    }

    /**
     * @dev Validates that the https://www.w3.org/TR/webauthn-2/#type[Type] field in the client data JSON
     * is set to "webauthn.get".
     */
    function validateExpectedTypeHash(bytes memory clientDataJSON, uint256 typeIndex) internal pure returns (bool) {
        // 21 = length of '"type":"webauthn.get"'
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
        if (challengeIndex + expectedChallengeBytes.length > clientDataJSON.length) return false;
        bytes memory actualChallengeBytes = Bytes.slice(
            clientDataJSON,
            challengeIndex,
            challengeIndex + expectedChallengeBytes.length
        );

        return Strings.equal(string(actualChallengeBytes), string(expectedChallengeBytes));
    }
}
