// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {P256} from "@openzeppelin/contracts/utils/cryptography/P256.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {WebAuthn} from "../../../contracts/utils/cryptography/WebAuthn.sol";

contract WebAuthnTest is Test {
    // solhint-disable-next-line quotes
    string internal constant PREFIX = '{"type":"webauthn.get","challenge":"';
    // solhint-disable-next-line quotes
    string internal constant SUFFIX = '"}';

    /// forge-config: default.fuzz.runs = 512
    function testFuzzVerifyMinimal(bytes memory challenge, uint256 seed) public view {
        // Generate private key and get public key
        uint256 privateKey = _asPrivateKey(seed);
        (uint256 x, uint256 y) = vm.publicKeyP256(privateKey);

        // Create authenticator data with minimum required length (37 bytes)
        bytes memory authenticatorData = new bytes(37);

        // Create client data JSON with required fields
        string memory clientDataJSON = string.concat(PREFIX, Base64.encodeURL(challenge), SUFFIX);

        // Sign the message
        bytes32 messageHash = sha256(abi.encodePacked(authenticatorData, sha256(bytes(clientDataJSON))));
        (bytes32 r, bytes32 s) = vm.signP256(privateKey, messageHash);

        // Create WebAuthnAuth struct
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: authenticatorData,
            clientDataJSON: clientDataJSON,
            challengeIndex: 23, // Position of challenge in clientDataJSON
            typeIndex: 1, // Position of type in clientDataJSON
            r: r,
            s: _ensureLowerS(s)
        });

        // Verify the signature
        assertTrue(WebAuthn.verifyMinimal(challenge, auth, bytes32(x), bytes32(y)));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzVerifyMinimalInvalidType(bytes memory challenge, uint256 seed) public view {
        // Generate private key and get public key
        uint256 privateKey = _asPrivateKey(seed);
        (uint256 x, uint256 y) = vm.publicKeyP256(privateKey);

        // Create authenticator data with minimum required length (37 bytes)
        bytes memory authenticatorData = new bytes(37);

        // Create client data JSON with invalid type
        string memory clientDataJSON = string.concat(
            // solhint-disable-next-line quotes
            '{"type":"webauthn.create","challenge":"',
            Base64.encodeURL(challenge),
            SUFFIX
        );

        // Sign the message
        bytes32 messageHash = sha256(abi.encodePacked(authenticatorData, sha256(bytes(clientDataJSON))));
        (bytes32 r, bytes32 s) = vm.signP256(privateKey, messageHash);

        // Create WebAuthnAuth struct
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: authenticatorData,
            clientDataJSON: clientDataJSON,
            challengeIndex: 23, // Position of challenge in clientDataJSON
            typeIndex: 1, // Position of type in clientDataJSON
            r: r,
            s: _ensureLowerS(s)
        });

        // Verify the signature should fail due to invalid type
        assertFalse(WebAuthn.verifyMinimal(challenge, auth, bytes32(x), bytes32(y)));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzVerifyMinimalInvalidChallenge(bytes memory challenge, uint256 seed) public view {
        // Generate private key and get public key
        uint256 privateKey = _asPrivateKey(seed);
        (uint256 x, uint256 y) = vm.publicKeyP256(privateKey);

        // Create authenticator data with minimum required length (37 bytes)
        bytes memory authenticatorData = new bytes(37);

        // Create client data JSON with invalid challenge
        string memory clientDataJSON = string.concat(PREFIX, Base64.encodeURL(bytes("invalid_challenge")), SUFFIX);

        // Sign the message
        bytes32 messageHash = sha256(abi.encodePacked(authenticatorData, sha256(bytes(clientDataJSON))));
        (bytes32 r, bytes32 s) = vm.signP256(privateKey, messageHash);

        // Create WebAuthnAuth struct
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: authenticatorData,
            clientDataJSON: clientDataJSON,
            challengeIndex: 23, // Position of challenge in clientDataJSON
            typeIndex: 1, // Position of type in clientDataJSON
            r: r,
            s: _ensureLowerS(s)
        });

        // Verify the signature should fail due to invalid challenge
        assertFalse(WebAuthn.verifyMinimal(challenge, auth, bytes32(x), bytes32(y)));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzVerify(bytes memory challenge, uint256 seed) public view {
        // Generate private key and get public key
        uint256 privateKey = _asPrivateKey(seed);
        (uint256 x, uint256 y) = vm.publicKeyP256(privateKey);

        // Create authenticator data with minimum required length (37 bytes)
        bytes memory authenticatorData = new bytes(37);
        // Set User Present flag
        authenticatorData[32] = bytes1(0x01);

        // Create client data JSON with required fields
        string memory clientDataJSON = string.concat(PREFIX, Base64.encodeURL(challenge), SUFFIX);

        // Sign the message
        bytes32 messageHash = sha256(abi.encodePacked(authenticatorData, sha256(bytes(clientDataJSON))));
        (bytes32 r, bytes32 s) = vm.signP256(privateKey, messageHash);
        s = _ensureLowerS(s);

        // Create WebAuthnAuth struct
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: authenticatorData,
            clientDataJSON: clientDataJSON,
            challengeIndex: 23, // Position of challenge in clientDataJSON
            typeIndex: 1, // Position of type in clientDataJSON
            r: r,
            s: s
        });

        // Verify the signature
        assertTrue(WebAuthn.verify(challenge, auth, bytes32(x), bytes32(y)));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzVerifyFailsWhenUpNotSet(bytes memory challenge, uint256 seed) public view {
        // Generate private key and get public key
        uint256 privateKey = _asPrivateKey(seed);
        (uint256 x, uint256 y) = vm.publicKeyP256(privateKey);

        // Create authenticator data with minimum required length (37 bytes)
        bytes memory authenticatorData = new bytes(37);
        // Don't set User Present flag

        // Create client data JSON with required fields
        string memory clientDataJSON = string.concat(PREFIX, Base64.encodeURL(challenge), SUFFIX);

        // Sign the message
        bytes32 messageHash = sha256(abi.encodePacked(authenticatorData, sha256(bytes(clientDataJSON))));
        (bytes32 r, bytes32 s) = vm.signP256(privateKey, messageHash);
        s = _ensureLowerS(s);

        // Create WebAuthnAuth struct
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: authenticatorData,
            clientDataJSON: clientDataJSON,
            challengeIndex: 23, // Position of challenge in clientDataJSON
            typeIndex: 1, // Position of type in clientDataJSON
            r: r,
            s: s
        });

        // Verify the signature should fail due to missing UP flag
        assertFalse(WebAuthn.verify(challenge, auth, bytes32(x), bytes32(y)));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzVerifyStrict(bytes memory challenge, uint256 seed) public view {
        // Generate private key and get public key
        uint256 privateKey = _asPrivateKey(seed);
        (uint256 x, uint256 y) = vm.publicKeyP256(privateKey);

        // Create authenticator data with minimum required length (37 bytes)
        bytes memory authenticatorData = new bytes(37);
        // Set User Present, User Verified, and Backup Eligibility flags
        authenticatorData[32] = bytes1(0x0D); // UP (0x01) + UV (0x04) + BE (0x08)

        // Create client data JSON with required fields
        string memory clientDataJSON = string.concat(PREFIX, Base64.encodeURL(challenge), SUFFIX);

        // Sign the message
        bytes32 messageHash = sha256(abi.encodePacked(authenticatorData, sha256(bytes(clientDataJSON))));
        (bytes32 r, bytes32 s) = vm.signP256(privateKey, messageHash);
        s = _ensureLowerS(s);

        // Create WebAuthnAuth struct
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: authenticatorData,
            clientDataJSON: clientDataJSON,
            challengeIndex: 23, // Position of challenge in clientDataJSON
            typeIndex: 1, // Position of type in clientDataJSON
            r: r,
            s: s
        });

        // Verify the signature
        assertTrue(WebAuthn.verifyStrict(challenge, auth, bytes32(x), bytes32(y)));
    }

    function testFuzzVerifyStrictFailsWithoutUV(bytes memory challenge, uint256 seed) public view {
        // Generate private key and get public key
        uint256 privateKey = _asPrivateKey(seed);
        (uint256 x, uint256 y) = vm.publicKeyP256(privateKey);

        // Create authenticator data with minimum required length (37 bytes)
        bytes memory authenticatorData = new bytes(37);
        // Set only User Present flag, but not User Verified
        authenticatorData[32] = bytes1(0x01); // Only UP (0x01) flag set

        // Create client data JSON with required fields
        string memory clientDataJSON = string.concat(PREFIX, Base64.encodeURL(challenge), SUFFIX);

        // Sign the message
        bytes32 messageHash = sha256(abi.encodePacked(authenticatorData, sha256(bytes(clientDataJSON))));
        (bytes32 r, bytes32 s) = vm.signP256(privateKey, messageHash);
        s = _ensureLowerS(s);

        // Create WebAuthnAuth struct
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: authenticatorData,
            clientDataJSON: clientDataJSON,
            challengeIndex: 23, // Position of challenge in clientDataJSON
            typeIndex: 1, // Position of type in clientDataJSON
            r: r,
            s: s
        });

        // Verify the signature should fail due to missing UV flag
        assertFalse(WebAuthn.verifyStrict(challenge, auth, bytes32(x), bytes32(y)));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzVerifyStrictFailsWithInvalidBEBS(bytes memory challenge, uint256 seed) public view {
        // Generate private key and get public key
        uint256 privateKey = _asPrivateKey(seed);
        (uint256 x, uint256 y) = vm.publicKeyP256(privateKey);

        // Create authenticator data with minimum required length (37 bytes)
        bytes memory authenticatorData = new bytes(37);
        // Set UP, UV flags and invalid BE/BS combination (BE=0, BS=1)
        authenticatorData[32] = bytes1(0x15); // UP (0x01) + UV (0x04) + BS (0x10) flags set

        // Create client data JSON with required fields
        string memory clientDataJSON = string.concat(PREFIX, Base64.encodeURL(challenge), SUFFIX);

        // Sign the message
        bytes32 messageHash = sha256(abi.encodePacked(authenticatorData, sha256(bytes(clientDataJSON))));
        (bytes32 r, bytes32 s) = vm.signP256(privateKey, messageHash);
        s = _ensureLowerS(s);

        // Create WebAuthnAuth struct
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: authenticatorData,
            clientDataJSON: clientDataJSON,
            challengeIndex: 23,
            typeIndex: 1,
            r: r,
            s: s
        });

        // Verify the signature should fail due to invalid BE/BS combination
        assertFalse(WebAuthn.verifyStrict(challenge, auth, bytes32(x), bytes32(y)));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzVerifyStrictSucceedsWithValidBEBSCombinations(bytes memory challenge, uint256 seed) public view {
        // Generate private key and get public key
        uint256 privateKey = _asPrivateKey(seed);
        (uint256 x, uint256 y) = vm.publicKeyP256(privateKey);

        // Create authenticator data with minimum required length (37 bytes)
        bytes memory authenticatorData = new bytes(37);
        // Set UP, UV flags and valid BE/BS combinations
        // Test all valid combinations: (BE=1,BS=0), (BE=1,BS=1), (BE=0,BS=0)
        authenticatorData[32] = bytes1(0x0D); // UP (0x01) + UV (0x04) + BE (0x08) flags set

        // Create client data JSON with required fields
        string memory clientDataJSON = string.concat(PREFIX, Base64.encodeURL(challenge), SUFFIX);

        // Sign the message
        bytes32 messageHash = sha256(abi.encodePacked(authenticatorData, sha256(bytes(clientDataJSON))));
        (bytes32 r, bytes32 s) = vm.signP256(privateKey, messageHash);
        s = _ensureLowerS(s);

        // Create WebAuthnAuth struct
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: authenticatorData,
            clientDataJSON: clientDataJSON,
            challengeIndex: 23,
            typeIndex: 1,
            r: r,
            s: s
        });

        // Verify the signature should succeed with valid BE/BS combination
        assertTrue(WebAuthn.verifyStrict(challenge, auth, bytes32(x), bytes32(y)));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzVerifyStrictSucceedsWithAllFlagsSet(bytes memory challenge, uint256 seed) public view {
        // Generate private key and get public key
        uint256 privateKey = _asPrivateKey(seed);
        (uint256 x, uint256 y) = vm.publicKeyP256(privateKey);

        // Create authenticator data with minimum required length (37 bytes)
        bytes memory authenticatorData = new bytes(37);
        // Set all flags: UP, UV, BE, BS
        authenticatorData[32] = bytes1(0x1D); // UP (0x01) + UV (0x04) + BE (0x08) + BS (0x10) flags set

        // Create client data JSON with required fields
        string memory clientDataJSON = string.concat(PREFIX, Base64.encodeURL(challenge), SUFFIX);

        // Sign the message
        bytes32 messageHash = sha256(abi.encodePacked(authenticatorData, sha256(bytes(clientDataJSON))));
        (bytes32 r, bytes32 s) = vm.signP256(privateKey, messageHash);
        s = _ensureLowerS(s);

        // Create WebAuthnAuth struct
        WebAuthn.WebAuthnAuth memory auth = WebAuthn.WebAuthnAuth({
            authenticatorData: authenticatorData,
            clientDataJSON: clientDataJSON,
            challengeIndex: 23,
            typeIndex: 1,
            r: r,
            s: s
        });

        // Verify the signature should succeed with all flags set
        assertTrue(WebAuthn.verifyStrict(challenge, auth, bytes32(x), bytes32(y)));
    }

    function _asPrivateKey(uint256 seed) private pure returns (uint256) {
        return bound(seed, 1, P256.N - 1);
    }

    function _ensureLowerS(bytes32 s) private pure returns (bytes32) {
        uint256 _s = uint256(s);
        unchecked {
            return _s > P256.N / 2 ? bytes32(P256.N - _s) : s;
        }
    }
}
