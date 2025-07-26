// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZKJWTUtils} from "../../../contracts/utils/cryptography/ZKJWTUtils.sol";
import {JwtRegistry} from "@zk-email/zk-jwt/src/utils/JwtRegistry.sol";
import {JwtGroth16Verifier} from "@zk-email/zk-jwt/src/utils/JwtGroth16Verifier.sol";
import {JwtVerifier} from "@zk-email/zk-jwt/src/utils/JwtVerifier.sol";
import {IVerifier, EmailProof} from "@zk-email/zk-jwt/src/interfaces/IVerifier.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CommandUtils} from "@zk-email/email-tx-builder/src/libraries/CommandUtils.sol";

contract ZKJWTUtilsTest is Test {
    using Strings for *;

    // Base field size
    uint256 constant Q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    JwtRegistry private _jwtRegistry;
    IVerifier private _verifier;
    bytes32 private _accountSalt;

    string private _kid = "12345";
    string private _iss = "https://example.com";
    string private _azp = "client-id-12345";
    string private _domainName = "12345|https://example.com|client-id-12345"; // kid|iss|azp format
    bytes32 private _publicKeyHash = 0x0ea9c777dc7110e5a9e89b13f0cfc540e3845ba120b2b6dc24024d61488d4788;
    bytes32 private _emailNullifier = 0x00a83fce3d4b1c9ef0f600644c1ecc6c8115b57b1596e0e3295e2c5105fbfd8a;
    bytes private _mockProof;

    string private constant SIGN_HASH_COMMAND = "signHash ";

    function setUp() public {
        // Deploy JWT Registry
        _jwtRegistry = _createJwtRegistry();

        // Deploy Verifier
        _verifier = _createVerifier();

        // Generate test data
        _accountSalt = keccak256("test@example.com");
        _mockProof = abi.encodePacked(bytes1(0x01));
    }

    function testIsValidZKJWTSignHash(
        bytes32 hash,
        uint256 timestamp,
        bytes32 emailNullifier,
        bytes32 accountSalt,
        bool isCodeExist,
        bytes memory proof
    ) public {
        // Build JWT proof with fuzzed parameters
        EmailProof memory jwtProof = _buildJWTProofMock(string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()));

        // Override with fuzzed values
        jwtProof.timestamp = timestamp;
        jwtProof.emailNullifier = emailNullifier;
        jwtProof.accountSalt = accountSalt;
        jwtProof.isCodeExist = isCodeExist;
        jwtProof.proof = proof;

        _mockVerifyEmailProof(jwtProof);

        // Test default signHash validation
        ZKJWTUtils.JWTProofError err = ZKJWTUtils.isValidZKJWT(jwtProof, _jwtRegistry, _verifier, hash);

        assertEq(uint256(err), uint256(ZKJWTUtils.JWTProofError.NoError));
    }

    function testIsValidZKJWTWithTemplate(
        bytes32 hash,
        uint256 timestamp,
        bytes32 emailNullifier,
        bytes32 accountSalt,
        bool isCodeExist,
        bytes memory proof
    ) public {
        // Use a simple, predictable command prefix
        string memory commandPrefix = "testCmd";

        string[] memory template = new string[](1);
        template[0] = CommandUtils.UINT_MATCHER;

        bytes[] memory templateParams = new bytes[](1);
        templateParams[0] = abi.encode(hash);

        EmailProof memory jwtProof = _buildJWTProofMock(string.concat(commandPrefix, " ", uint256(hash).toString()));

        // Override with fuzzed values
        jwtProof.timestamp = timestamp;
        jwtProof.emailNullifier = emailNullifier;
        jwtProof.accountSalt = accountSalt;
        jwtProof.isCodeExist = isCodeExist;
        jwtProof.proof = proof;

        _mockVerifyEmailProof(jwtProof);

        ZKJWTUtils.JWTProofError err = ZKJWTUtils.isValidZKJWT(
            jwtProof,
            _jwtRegistry,
            _verifier,
            template,
            templateParams
        );

        assertEq(uint256(err), uint256(ZKJWTUtils.JWTProofError.NoError));
    }

    function testCommandMatchWithDifferentCases(
        address addr,
        uint256 timestamp,
        bytes32 emailNullifier,
        bytes32 accountSalt,
        bool isCodeExist,
        bytes memory proof
    ) public {
        string memory commandPrefix = "authorize";

        string[] memory template = new string[](1);
        template[0] = CommandUtils.ETH_ADDR_MATCHER;

        bytes[] memory templateParams = new bytes[](1);
        templateParams[0] = abi.encode(addr);

        // Test with different cases
        for (uint256 i = 0; i < uint8(type(ZKJWTUtils.Case).max); i++) {
            EmailProof memory jwtProof = _buildJWTProofMock(
                string.concat(commandPrefix, " ", CommandUtils.addressToHexString(addr, i))
            );

            // Override with fuzzed values
            jwtProof.timestamp = timestamp;
            jwtProof.emailNullifier = emailNullifier;
            jwtProof.accountSalt = accountSalt;
            jwtProof.isCodeExist = isCodeExist;
            jwtProof.proof = proof;

            _mockVerifyEmailProof(jwtProof);

            ZKJWTUtils.JWTProofError err = ZKJWTUtils.isValidZKJWT(
                jwtProof,
                _jwtRegistry,
                _verifier,
                template,
                templateParams,
                ZKJWTUtils.Case(i)
            );
            assertEq(uint256(err), uint256(ZKJWTUtils.JWTProofError.NoError));
        }
    }

    function testInvalidJWTPublicKeyHash(bytes32 hash, bytes32 publicKeyHash) public view {
        // Ensure we use a different public key hash than the registered one
        vm.assume(publicKeyHash != _publicKeyHash);

        EmailProof memory jwtProof = _buildJWTProofMock(string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()));
        jwtProof.publicKeyHash = publicKeyHash;

        ZKJWTUtils.JWTProofError err = ZKJWTUtils.isValidZKJWT(jwtProof, _jwtRegistry, _verifier, hash);

        assertEq(uint256(err), uint256(ZKJWTUtils.JWTProofError.JWTPublicKeyHash));
    }

    function testInvalidMaskedCommandLength(bytes32 hash, uint256 length) public view {
        length = bound(length, 606, 1000); // Assuming commandBytes is 605

        EmailProof memory jwtProof = _buildJWTProofMock(string(new bytes(length)));

        ZKJWTUtils.JWTProofError err = ZKJWTUtils.isValidZKJWT(jwtProof, _jwtRegistry, _verifier, hash);

        assertEq(uint256(err), uint256(ZKJWTUtils.JWTProofError.MaskedCommandLength));
    }

    // function testMismatchedCommand(bytes32 hash) public view {
    //     // Use a fixed invalid command that won't match signHash pattern
    //     string memory invalidCommand = string(abi.encodePacked("invalidJWTCommand ", uint256(hash).toString()));

    //     EmailProof memory jwtProof = _buildJWTProofMock(invalidCommand);

    //     ZKJWTUtils.JWTProomnfError err = ZKJWTUtils.isValidZKJWT(jwtProof, _jwtRegistry, _verifier, hash);

    //     assertEq(uint256(err), uint256(ZKJWTUtils.JWTProofError.MismatchedCommand));
    // }

    function testMismatchedCommandWithTemplate(bytes32 hash) public view {
        string[] memory template = new string[](1);
        template[0] = CommandUtils.UINT_MATCHER;

        bytes[] memory templateParams = new bytes[](1);
        templateParams[0] = abi.encode(uint256(12345)); // Different value than what's in command

        EmailProof memory jwtProof = _buildJWTProofMock(string(abi.encodePacked("testCmd", " ", hash))); // Different from templateParams

        ZKJWTUtils.JWTProofError err = ZKJWTUtils.isValidZKJWT(
            jwtProof,
            _jwtRegistry,
            _verifier,
            template,
            templateParams
        );

        assertEq(uint256(err), uint256(ZKJWTUtils.JWTProofError.MismatchedCommand));
    }

    // function testInvalidJWTProof(
    //     bytes32 hash,
    //     uint256[2] memory pA,
    //     uint256[2][2] memory pB,
    //     uint256[2] memory pC
    // ) public view {
    //     pA[0] = bound(pA[0], 1, Q - 1);
    //     pA[1] = bound(pA[1], 1, Q - 1);
    //     pB[0][0] = bound(pB[0][0], 1, Q - 1);
    //     pB[0][1] = bound(pB[0][1], 1, Q - 1);
    //     pB[1][0] = bound(pB[1][0], 1, Q - 1);
    //     pB[1][1] = bound(pB[1][1], 1, Q - 1);
    //     pC[0] = bound(pC[0], 1, Q - 1);
    //     pC[1] = bound(pC[1], 1, Q - 1);

    //     EmailProof memory jwtProof = _buildJWTProofMock(string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()));

    //     jwtProof.proof = abi.encode(pA, pB, pC);

    //     ZKJWTUtils.JWTProofError err = ZKJWTUtils.isValidZKJWT(jwtProof, _jwtRegistry, _verifier, hash);

    //     assertEq(uint256(err), uint256(ZKJWTUtils.JWTProofError.JWTProof));
    // }

    function testComplexJWTCommand(
        uint256 amount,
        address recipient,
        uint256 timestamp,
        bytes32 emailNullifier,
        bytes32 accountSalt,
        bool isCodeExist,
        bytes memory proof
    ) public {
        string[] memory template = new string[](4);
        template[0] = CommandUtils.UINT_MATCHER;
        template[1] = "ETH";
        template[2] = "to";
        template[3] = CommandUtils.ETH_ADDR_MATCHER;

        bytes[] memory templateParams = new bytes[](2);
        templateParams[0] = abi.encode(amount);
        templateParams[1] = abi.encode(recipient);

        EmailProof memory jwtProof = _buildJWTProofMock(
            string.concat("Send ", amount.toString(), " ETH to ", recipient.toHexString())
        );

        // Override with fuzzed values
        jwtProof.timestamp = timestamp;
        jwtProof.emailNullifier = emailNullifier;
        jwtProof.accountSalt = accountSalt;
        jwtProof.isCodeExist = isCodeExist;
        jwtProof.proof = proof;

        _mockVerifyEmailProof(jwtProof);

        ZKJWTUtils.JWTProofError err = ZKJWTUtils.isValidZKJWT(
            jwtProof,
            _jwtRegistry,
            _verifier,
            template,
            templateParams
        );

        assertEq(uint256(err), uint256(ZKJWTUtils.JWTProofError.NoError));
    }

    function _createVerifier() private returns (IVerifier) {
        JwtVerifier verifier = new JwtVerifier();
        JwtGroth16Verifier groth16Verifier = new JwtGroth16Verifier();
        verifier.initialize(msg.sender, address(groth16Verifier));
        return verifier;
    }

    function _createJwtRegistry() private returns (JwtRegistry) {
        JwtRegistry jwtRegistry = new JwtRegistry(address(this));
        jwtRegistry.setJwtPublicKey(_domainName, _publicKeyHash);
        return jwtRegistry;
    }

    function _mockVerifyEmailProof(EmailProof memory jwtProof) private {
        vm.mockCall(address(_verifier), abi.encodeCall(IVerifier.verifyEmailProof, (jwtProof)), abi.encode(true));
    }

    function _buildJWTProofMock(string memory command) private view returns (EmailProof memory jwtProof) {
        jwtProof = EmailProof({
            domainName: _domainName,
            publicKeyHash: _publicKeyHash,
            timestamp: block.timestamp,
            maskedCommand: command,
            emailNullifier: _emailNullifier,
            accountSalt: _accountSalt,
            isCodeExist: true,
            proof: _mockProof
        });
    }
}
