// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZKEmailUtils} from "../../../contracts/utils/cryptography/ZKEmailUtils.sol";
import {ECDSAOwnedDKIMRegistry} from "@zk-email/email-tx-builder/utils/ECDSAOwnedDKIMRegistry.sol";
import {Groth16Verifier} from "@zk-email/email-tx-builder/utils/Groth16Verifier.sol";
import {Verifier, EmailProof} from "@zk-email/email-tx-builder/utils/Verifier.sol";
import {EmailAuthMsg} from "@zk-email/email-tx-builder/interfaces/IEmailTypes.sol";
import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IVerifier, EmailProof} from "@zk-email/email-tx-builder/interfaces/IVerifier.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CommandUtils} from "@zk-email/email-tx-builder/libraries/CommandUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ZKEmailUtilsTest is Test {
    using Strings for uint256;
    using ZKEmailUtils for EmailAuthMsg;

    // Base field size
    uint256 constant Q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    IDKIMRegistry private _dkimRegistry;
    IVerifier private _verifier;
    bytes32 private _accountSalt;
    uint256 private _templateId;
    bytes32 private _publicKeyHash;
    bytes32 private _emailNullifier;
    bytes private _mockProof;

    string private constant SIGN_HASH_COMMAND = "signHash ";

    function setUp() public {
        // Deploy DKIM Registry
        _dkimRegistry = _createECDSAOwnedDKIMRegistry();

        // Deploy Verifier
        _verifier = _createVerifier();

        // Generate test data
        _accountSalt = keccak256("test@example.com");
        _templateId = 1;
        _publicKeyHash = keccak256("publicKey");
        _emailNullifier = keccak256("emailNullifier");
        _mockProof = abi.encodePacked(bytes1(0x01));
    }

    function buildEmailAuthMsg(
        string memory command,
        bytes[] memory params,
        uint256 skippedPrefix
    ) public view returns (EmailAuthMsg memory emailAuthMsg) {
        EmailProof memory emailProof = EmailProof({
            domainName: "gmail.com",
            publicKeyHash: _publicKeyHash,
            timestamp: block.timestamp,
            maskedCommand: command,
            emailNullifier: _emailNullifier,
            accountSalt: _accountSalt,
            isCodeExist: true,
            proof: _mockProof
        });

        emailAuthMsg = EmailAuthMsg({
            templateId: _templateId,
            commandParams: params,
            skippedCommandPrefix: skippedPrefix,
            proof: emailProof
        });
    }

    function testIsValidZKEmailSignHash(
        bytes32 hash,
        string memory domainName,
        bytes32 publicKeyHash,
        uint256 timestamp,
        bytes32 emailNullifier,
        bytes32 accountSalt,
        bool isCodeExist,
        bytes memory proof
    ) public {
        // Build email auth message with fuzzed parameters
        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = buildEmailAuthMsg(
            string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()),
            commandParams,
            0
        );

        // Override with fuzzed values
        emailAuthMsg.proof.domainName = domainName;
        emailAuthMsg.proof.publicKeyHash = publicKeyHash;
        emailAuthMsg.proof.timestamp = timestamp;
        emailAuthMsg.proof.emailNullifier = emailNullifier;
        emailAuthMsg.proof.accountSalt = accountSalt;
        emailAuthMsg.proof.isCodeExist = isCodeExist;
        emailAuthMsg.proof.proof = proof;

        _mockIsDKIMPublicKeyHashValid(emailAuthMsg.proof.domainName, emailAuthMsg.proof.publicKeyHash);
        _mockVerifyEmailProof(emailAuthMsg.proof);

        // Test validation
        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            IVerifier(_verifier)
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
    }

    function testIsValidZKEmailWithTemplate(
        bytes32 hash,
        string memory domainName,
        bytes32 publicKeyHash,
        uint256 timestamp,
        bytes32 emailNullifier,
        bytes32 accountSalt,
        bool isCodeExist,
        bytes memory proof,
        string memory commandPrefix
    ) public {
        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = buildEmailAuthMsg(
            string.concat(commandPrefix, " ", uint256(hash).toString()),
            commandParams,
            0
        );

        // Override with fuzzed values
        emailAuthMsg.proof.domainName = domainName;
        emailAuthMsg.proof.publicKeyHash = publicKeyHash;
        emailAuthMsg.proof.timestamp = timestamp;
        emailAuthMsg.proof.emailNullifier = emailNullifier;
        emailAuthMsg.proof.accountSalt = accountSalt;
        emailAuthMsg.proof.isCodeExist = isCodeExist;
        emailAuthMsg.proof.proof = proof;

        string[] memory template = new string[](2);
        template[0] = commandPrefix;
        template[1] = CommandUtils.UINT_MATCHER;

        _mockIsDKIMPublicKeyHashValid(emailAuthMsg.proof.domainName, emailAuthMsg.proof.publicKeyHash);
        _mockVerifyEmailProof(emailAuthMsg.proof);

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            IVerifier(_verifier),
            template
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
    }

    function testCommandMatchWithDifferentCases(
        bytes32 hash,
        string memory domainName,
        bytes32 publicKeyHash,
        uint256 timestamp,
        bytes32 emailNullifier,
        bytes32 accountSalt,
        bool isCodeExist,
        bytes memory proof,
        string memory commandPrefix
    ) public {
        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = buildEmailAuthMsg(
            string.concat(commandPrefix, " ", uint256(hash).toString()),
            commandParams,
            0
        );

        // Override with fuzzed values
        emailAuthMsg.proof.domainName = domainName;
        emailAuthMsg.proof.publicKeyHash = publicKeyHash;
        emailAuthMsg.proof.timestamp = timestamp;
        emailAuthMsg.proof.emailNullifier = emailNullifier;
        emailAuthMsg.proof.accountSalt = accountSalt;
        emailAuthMsg.proof.isCodeExist = isCodeExist;
        emailAuthMsg.proof.proof = proof;

        _mockIsDKIMPublicKeyHashValid(emailAuthMsg.proof.domainName, emailAuthMsg.proof.publicKeyHash);
        _mockVerifyEmailProof(emailAuthMsg.proof);

        string[] memory template = new string[](2);
        template[0] = commandPrefix;
        template[1] = CommandUtils.UINT_MATCHER;

        // Test with different cases
        for (uint256 i = 0; i < uint8(type(ZKEmailUtils.Case).max) - 1; i++) {
            ZKEmailUtils.Case stringCase = ZKEmailUtils.Case(i);
            ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
                emailAuthMsg,
                IDKIMRegistry(_dkimRegistry),
                IVerifier(_verifier),
                template,
                stringCase
            );
            assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
        }
    }

    function testCommandMatchWithAnyCase(
        bytes32 hash,
        string memory domainName,
        bytes32 publicKeyHash,
        uint256 timestamp,
        bytes32 emailNullifier,
        bytes32 accountSalt,
        bool isCodeExist,
        bytes memory proof,
        string memory commandPrefix
    ) public {
        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = buildEmailAuthMsg(
            string.concat(commandPrefix, " ", uint256(hash).toString()),
            commandParams,
            0
        );

        // Override with fuzzed values
        emailAuthMsg.proof.domainName = domainName;
        emailAuthMsg.proof.publicKeyHash = publicKeyHash;
        emailAuthMsg.proof.timestamp = timestamp;
        emailAuthMsg.proof.emailNullifier = emailNullifier;
        emailAuthMsg.proof.accountSalt = accountSalt;
        emailAuthMsg.proof.isCodeExist = isCodeExist;
        emailAuthMsg.proof.proof = proof;

        string[] memory template = new string[](2);
        template[0] = commandPrefix;
        template[1] = CommandUtils.UINT_MATCHER;

        _mockIsDKIMPublicKeyHashValid(emailAuthMsg.proof.domainName, emailAuthMsg.proof.publicKeyHash);
        _mockVerifyEmailProof(emailAuthMsg.proof);

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            IVerifier(_verifier),
            template,
            ZKEmailUtils.Case.ANY
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
    }

    function testInvalidDKIMPublicKeyHash(bytes32 hash, string memory domainName, bytes32 publicKeyHash) public view {
        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = buildEmailAuthMsg(
            string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()),
            commandParams,
            0
        );

        emailAuthMsg.proof.domainName = domainName;
        emailAuthMsg.proof.publicKeyHash = publicKeyHash;

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            IVerifier(_verifier)
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.DKIMPublicKeyHash));
    }

    function testInvalidMaskedCommandLength(bytes32 hash, uint256 length) public view {
        length = bound(length, 606, 1000); // Assuming commandBytes is 605

        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = buildEmailAuthMsg(string(new bytes(length)), commandParams, 0);

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            IVerifier(_verifier)
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.MaskedCommandLength));
    }

    function testSkippedCommandPrefix(bytes32 hash, uint256 skippedPrefix) public view {
        uint256 verifierCommandBytes = _verifier.commandBytes();
        skippedPrefix = bound(skippedPrefix, verifierCommandBytes, verifierCommandBytes + 1000);

        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = buildEmailAuthMsg(
            string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()),
            commandParams,
            skippedPrefix
        );

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            IVerifier(_verifier)
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.SkippedCommandPrefixSize));
    }

    function testMismatchedCommand(bytes32 hash, string memory invalidCommand) public view {
        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = buildEmailAuthMsg(invalidCommand, commandParams, 0);

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            IVerifier(_verifier)
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.MismatchedCommand));
    }

    function testInvalidEmailProof(
        bytes32 hash,
        uint256[2] memory pA,
        uint256[2][2] memory pB,
        uint256[2] memory pC
    ) public {
        // TODO: Remove these when the Verifier wrapper does not revert.
        pA[0] = bound(pA[0], 1, Q - 1);
        pA[1] = bound(pA[1], 1, Q - 1);
        pB[0][0] = bound(pB[0][0], 1, Q - 1);
        pB[0][1] = bound(pB[0][1], 1, Q - 1);
        pB[1][0] = bound(pB[1][0], 1, Q - 1);
        pB[1][1] = bound(pB[1][1], 1, Q - 1);
        pC[0] = bound(pC[0], 1, Q - 1);
        pC[1] = bound(pC[1], 1, Q - 1);

        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = buildEmailAuthMsg(
            string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()),
            commandParams,
            0
        );

        emailAuthMsg.proof.proof = abi.encode(pA, pB, pC);

        _mockIsDKIMPublicKeyHashValid(emailAuthMsg.proof.domainName, emailAuthMsg.proof.publicKeyHash);

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            IVerifier(_verifier)
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.EmailProof));
    }

    function _createVerifier() private returns (IVerifier) {
        Verifier verifier = new Verifier();
        Groth16Verifier groth16Verifier = new Groth16Verifier();
        verifier.initialize(msg.sender, address(groth16Verifier));
        return verifier;
    }

    function _createECDSAOwnedDKIMRegistry() private returns (IDKIMRegistry) {
        ECDSAOwnedDKIMRegistry ecdsaDkim = new ECDSAOwnedDKIMRegistry();
        ecdsaDkim.initialize(msg.sender, msg.sender);
        return ecdsaDkim;
    }

    function _mockIsDKIMPublicKeyHashValid(string memory domainName, bytes32 publicKeyHash) private {
        vm.mockCall(
            address(_dkimRegistry),
            abi.encodeCall(IDKIMRegistry.isDKIMPublicKeyHashValid, (domainName, publicKeyHash)),
            abi.encode(true)
        );
    }

    function _mockVerifyEmailProof(EmailProof memory emailProof) private {
        vm.mockCall(address(_verifier), abi.encodeCall(IVerifier.verifyEmailProof, (emailProof)), abi.encode(true));
    }
}
