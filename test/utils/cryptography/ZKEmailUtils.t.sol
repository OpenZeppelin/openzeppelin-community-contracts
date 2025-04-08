// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZKEmailUtils} from "../../../contracts/utils/cryptography/ZKEmailUtils.sol";
import {EmailProof} from "@zk-email/email-tx-builder/utils/Verifier.sol";
import {EmailAuthMsg} from "@zk-email/email-tx-builder/interfaces/IEmailTypes.sol";
import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IVerifier, EmailProof} from "@zk-email/email-tx-builder/interfaces/IVerifier.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CommandUtils} from "@zk-email/email-tx-builder/libraries/CommandUtils.sol";

contract ZKEmailUtilsTest is Test {
    using Strings for uint256;
    using ZKEmailUtils for EmailAuthMsg;

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
        _dkimRegistry = IDKIMRegistry(address(new MockDKIMRegistry()));

        // Deploy Verifier
        _verifier = IVerifier(address(new MockVerifier()));

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
    ) public view {
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
    ) public view {
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
    ) public view {
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
    ) public view {
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

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            IVerifier(_verifier),
            template,
            ZKEmailUtils.Case.ANY
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
    }

    function testInvalidDKIMPublicKeyHash(bytes32 hash, string memory domainName, bytes32 publicKeyHash) public {
        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = buildEmailAuthMsg(
            string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()),
            commandParams,
            0
        );

        emailAuthMsg.proof.domainName = domainName;
        emailAuthMsg.proof.publicKeyHash = publicKeyHash;

        // Mock DKIM registry to return false
        vm.mockCall(
            address(_dkimRegistry),
            abi.encodeCall(IDKIMRegistry.isDKIMPublicKeyHashValid, (domainName, publicKeyHash)),
            abi.encode(false)
        );

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

    function testSkippedCommandPrefix(bytes32 hash, uint256 skippedPrefix) public {
        skippedPrefix = bound(skippedPrefix, 606, 1000); // Assuming commandBytes is 605

        vm.mockCall(address(_verifier), abi.encodeCall(IVerifier.commandBytes, ()), abi.encode(skippedPrefix));

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

    function testInvalidEmailProof(bytes32 hash, bytes memory invalidProof) public {
        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = buildEmailAuthMsg(
            string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()),
            commandParams,
            0
        );

        emailAuthMsg.proof.proof = invalidProof;

        // Mock verifier to return false
        vm.mockCall(
            address(_verifier),
            abi.encodeCall(IVerifier.verifyEmailProof, (emailAuthMsg.proof)),
            abi.encode(false)
        );

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            IVerifier(_verifier)
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.EmailProof));
    }
}

// Mock DKIM Registry for testing
contract MockDKIMRegistry is IDKIMRegistry {
    function isDKIMPublicKeyHashValid(
        string memory /* domainName */,
        bytes32 /* publicKeyHash */
    ) external pure returns (bool) {
        return true; // Always return true for testing
    }
}

// Mock Verifier for testing
contract MockVerifier is IVerifier {
    function commandBytes() external pure returns (uint256) {
        return 605;
    }

    function verifyEmailProof(EmailProof memory /* proof */) external pure returns (bool) {
        return true; // Always return true for testing
    }
}
