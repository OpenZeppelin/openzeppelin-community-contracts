// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZKEmailUtils} from "../../../contracts/utils/cryptography/ZKEmailUtils.sol";
import {ECDSAOwnedDKIMRegistry} from "@zk-email/email-tx-builder/src/utils/ECDSAOwnedDKIMRegistry.sol";
import {Groth16Verifier} from "@zk-email/email-tx-builder/test/fixtures/Groth16Verifier.sol";
import {IGroth16Verifier} from "@zk-email/email-tx-builder/src/interfaces/IGroth16Verifier.sol";
import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {EmailProof} from "@zk-email/email-tx-builder/src/interfaces/IEmailTypes.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CommandUtils} from "@zk-email/email-tx-builder/src/libraries/CommandUtils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EmailAuthMsgFixtures, EmailAuthMsg} from "@zk-email/email-tx-builder/test/fixtures/EmailAuthMsgFixtures.sol";

contract ZKEmailUtilsTest is Test {
    using Strings for *;
    using ZKEmailUtils for EmailAuthMsg;

    // Base field size
    uint256 constant Q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    IDKIMRegistry private _dkimRegistry;
    IGroth16Verifier private _verifier;
    bytes32 private _accountSalt;
    uint256 private _templateId;
    // From https://github.com/zkemail/email-tx-builder/blob/main/packages/contracts/test/helpers/DeploymentHelper.sol#L36-L41
    string private _selector = "1234";
    string private _domainName = "gmail.com";
    bytes32 private _publicKeyHash = 0x0ea9c777dc7110e5a9e89b13f0cfc540e3845ba120b2b6dc24024d61488d4788;
    bytes32 private _emailNullifier = 0x00a83fce3d4b1c9ef0f600644c1ecc6c8115b57b1596e0e3295e2c5105fbfd8a;
    bytes private _mockProof;

    string private constant SIGN_HASH_COMMAND = "signHash ";

    function setUp() public {
        // Deploy DKIM Registry
        _dkimRegistry = _createECDSAOwnedDKIMRegistry();

        // Deploy Verifier
        _verifier = IGroth16Verifier(address(new Groth16Verifier()));

        // Generate test data
        _accountSalt = keccak256("test@example.com");
        _templateId = 1;
        _mockProof = abi.encodePacked(bytes1(0x01));
    }

    function testFixtureCase1SignHash() public {
        EmailAuthMsg memory authMsg = EmailAuthMsgFixtures.getCase1();
        _setupDKIMRegistryForFixture(authMsg);
        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(authMsg, _dkimRegistry, _verifier);
        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
    }

    function testFixtureCase2SignHash() public {
        EmailAuthMsg memory authMsg = EmailAuthMsgFixtures.getCase2();
        _setupDKIMRegistryForFixture(authMsg);
        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(authMsg, _dkimRegistry, _verifier);
        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
    }

    function testFixtureCase3SendEthToAddr() public {
        EmailAuthMsg memory authMsg = EmailAuthMsgFixtures.getCase3();
        _setupDKIMRegistryForFixture(authMsg);

        string[] memory template = new string[](5);
        template[0] = "Send";
        template[1] = CommandUtils.DECIMALS_MATCHER;
        template[2] = "ETH";
        template[3] = "to";
        template[4] = CommandUtils.ETH_ADDR_MATCHER;

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            authMsg,
            _dkimRegistry,
            _verifier,
            template,
            ZKEmailUtils.Case.ANY
        );
        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
    }

    function testFixtureCase4AcceptGuardian() public {
        EmailAuthMsg memory authMsg = EmailAuthMsgFixtures.getCase4();
        _setupDKIMRegistryForFixture(authMsg);

        string[] memory template = new string[](3);
        template[0] = "Accept";
        template[1] = "guardian request for";
        template[2] = CommandUtils.ETH_ADDR_MATCHER;

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            authMsg,
            _dkimRegistry,
            _verifier,
            template,
            ZKEmailUtils.Case.ANY
        );
        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
    }

    function testIsValidZKEmailSignHash(
        bytes32 hash,
        uint256 timestamp,
        bytes32 emailNullifier,
        bytes32 accountSalt,
        bool isCodeExist,
        uint256[2] memory pA,
        uint256[2][2] memory pB,
        uint256[2] memory pC
    ) public {
        (pA, pB, pC) = _boundPoints(pA, pB, pC);
        bytes memory proof = abi.encode(pA, pB, pC);

        // Build email auth message with fuzzed parameters
        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = _buildEmailAuthMsgMock(
            string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()),
            commandParams,
            0
        );

        // Override with fuzzed values
        emailAuthMsg.proof.timestamp = timestamp;
        emailAuthMsg.proof.emailNullifier = emailNullifier;
        emailAuthMsg.proof.accountSalt = accountSalt;
        emailAuthMsg.proof.isCodeExist = isCodeExist;
        emailAuthMsg.proof.proof = proof;

        _mockVerifyEmailProof(emailAuthMsg.proof);

        // Test validation
        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            _verifier
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
    }

    function testIsValidZKEmailWithTemplate(
        bytes32 hash,
        uint256 timestamp,
        bytes32 emailNullifier,
        bytes32 accountSalt,
        bool isCodeExist,
        uint256[2] memory pA,
        uint256[2][2] memory pB,
        uint256[2] memory pC,
        string memory commandPrefix
    ) public {
        (pA, pB, pC) = _boundPoints(pA, pB, pC);
        bytes memory proof = abi.encode(pA, pB, pC);

        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = _buildEmailAuthMsgMock(
            string.concat(commandPrefix, " ", uint256(hash).toString()),
            commandParams,
            0
        );

        // Override with fuzzed values
        emailAuthMsg.proof.timestamp = timestamp;
        emailAuthMsg.proof.emailNullifier = emailNullifier;
        emailAuthMsg.proof.accountSalt = accountSalt;
        emailAuthMsg.proof.isCodeExist = isCodeExist;
        emailAuthMsg.proof.proof = proof;

        string[] memory template = new string[](2);
        template[0] = commandPrefix;
        template[1] = CommandUtils.UINT_MATCHER;

        _mockVerifyEmailProof(emailAuthMsg.proof);

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            _verifier,
            template
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
    }

    function testCommandMatchWithDifferentCases(
        address addr,
        uint256 timestamp,
        bytes32 emailNullifier,
        bytes32 accountSalt,
        bool isCodeExist,
        uint256[2] memory pA,
        uint256[2][2] memory pB,
        uint256[2] memory pC,
        string memory commandPrefix
    ) public {
        (pA, pB, pC) = _boundPoints(pA, pB, pC);
        bytes memory proof = abi.encode(pA, pB, pC);

        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(addr);

        // Test with different cases
        for (uint256 i = 0; i < uint8(type(ZKEmailUtils.Case).max) - 1; i++) {
            EmailAuthMsg memory emailAuthMsg = _buildEmailAuthMsgMock(
                string.concat(commandPrefix, " ", CommandUtils.addressToHexString(addr, i)),
                commandParams,
                0
            );

            // Override with fuzzed values
            emailAuthMsg.proof.timestamp = timestamp;
            emailAuthMsg.proof.emailNullifier = emailNullifier;
            emailAuthMsg.proof.accountSalt = accountSalt;
            emailAuthMsg.proof.isCodeExist = isCodeExist;
            emailAuthMsg.proof.proof = proof;

            _mockVerifyEmailProof(emailAuthMsg.proof);

            string[] memory template = new string[](2);
            template[0] = commandPrefix;
            template[1] = CommandUtils.ETH_ADDR_MATCHER;

            ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
                emailAuthMsg,
                IDKIMRegistry(_dkimRegistry),
                _verifier,
                template,
                ZKEmailUtils.Case(i)
            );
            assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
        }
    }

    function testCommandMatchWithAnyCase(
        address addr,
        uint256 timestamp,
        bytes32 emailNullifier,
        bytes32 accountSalt,
        bool isCodeExist,
        uint256[2] memory pA,
        uint256[2][2] memory pB,
        uint256[2] memory pC,
        string memory commandPrefix
    ) public {
        (pA, pB, pC) = _boundPoints(pA, pB, pC);
        bytes memory proof = abi.encode(pA, pB, pC);

        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(addr);

        EmailAuthMsg memory emailAuthMsg = _buildEmailAuthMsgMock(
            string.concat(commandPrefix, " ", addr.toHexString()),
            commandParams,
            0
        );

        // Override with fuzzed values
        emailAuthMsg.proof.timestamp = timestamp;
        emailAuthMsg.proof.emailNullifier = emailNullifier;
        emailAuthMsg.proof.accountSalt = accountSalt;
        emailAuthMsg.proof.isCodeExist = isCodeExist;
        emailAuthMsg.proof.proof = proof;

        string[] memory template = new string[](2);
        template[0] = commandPrefix;
        template[1] = CommandUtils.ETH_ADDR_MATCHER;

        _mockVerifyEmailProof(emailAuthMsg.proof);

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            _verifier,
            template,
            ZKEmailUtils.Case.ANY
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
    }

    function testInvalidDKIMPublicKeyHash(bytes32 hash, string memory domainName, bytes32 publicKeyHash) public view {
        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = _buildEmailAuthMsgMock(
            string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()),
            commandParams,
            0
        );

        emailAuthMsg.proof.domainName = domainName;
        emailAuthMsg.proof.publicKeyHash = publicKeyHash;

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            _verifier
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.DKIMPublicKeyHash));
    }

    function testInvalidMaskedCommandLength(bytes32 hash, uint256 length) public view {
        length = bound(length, 606, 1000); // Assuming commandBytes is 605

        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = _buildEmailAuthMsgMock(string(new bytes(length)), commandParams, 0);

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            _verifier
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.MaskedCommandLength));
    }

    function testSkippedCommandPrefix(bytes32 hash, uint256 skippedPrefix) public view {
        uint256 verifierCommandBytes = ZKEmailUtils.COMMAND_BYTES;
        skippedPrefix = bound(skippedPrefix, verifierCommandBytes, verifierCommandBytes + 1000);

        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = _buildEmailAuthMsgMock(
            string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()),
            commandParams,
            skippedPrefix
        );

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            _verifier
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.SkippedCommandPrefixSize));
    }

    function testMismatchedCommand(bytes32 hash, string memory invalidCommand) public view {
        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = _buildEmailAuthMsgMock(invalidCommand, commandParams, 0);

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            _verifier
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.MismatchedCommand));
    }

    function testInvalidEmailProof(
        bytes32 hash,
        uint256[2] memory pA,
        uint256[2][2] memory pB,
        uint256[2] memory pC
    ) public view {
        (pA, pB, pC) = _boundPoints(pA, pB, pC);

        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailAuthMsg memory emailAuthMsg = _buildEmailAuthMsgMock(
            string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()),
            commandParams,
            0
        );

        emailAuthMsg.proof.proof = abi.encode(pA, pB, pC);

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailAuthMsg,
            IDKIMRegistry(_dkimRegistry),
            _verifier
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.EmailProof));
    }

    function _createECDSAOwnedDKIMRegistry() private returns (IDKIMRegistry) {
        ECDSAOwnedDKIMRegistry ecdsaDkim = new ECDSAOwnedDKIMRegistry();
        (address alice, uint256 alicePk) = makeAddrAndKey("alice");
        ecdsaDkim.initialize(alice, alice);
        string memory prefix = ecdsaDkim.SET_PREFIX();
        string memory message = ecdsaDkim.computeSignedMsg(prefix, _domainName, _publicKeyHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, MessageHashUtils.toEthSignedMessageHash(bytes(message)));
        ecdsaDkim.setDKIMPublicKeyHash(_selector, _domainName, _publicKeyHash, abi.encodePacked(r, s, v));
        return ecdsaDkim;
    }

    function _mockVerifyEmailProof(EmailProof memory emailProof) private {
        vm.mockCall(
            address(_verifier),
            abi.encodeWithSelector(IGroth16Verifier.verifyProof.selector),
            abi.encode(true)
        );
    }

    function _buildEmailAuthMsgMock(
        string memory command,
        bytes[] memory params,
        uint256 skippedPrefix
    ) private view returns (EmailAuthMsg memory emailAuthMsg) {
        EmailProof memory emailProof = EmailProof({
            domainName: _domainName,
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

    function _setupDKIMRegistryForFixture(EmailAuthMsg memory fixture) private {
        if (!_dkimRegistry.isDKIMPublicKeyHashValid(fixture.proof.domainName, fixture.proof.publicKeyHash)) {
            (, uint256 alicePk) = makeAddrAndKey("alice");
            string memory prefix = ECDSAOwnedDKIMRegistry(address(_dkimRegistry)).SET_PREFIX();
            string memory message = ECDSAOwnedDKIMRegistry(address(_dkimRegistry)).computeSignedMsg(
                prefix,
                fixture.proof.domainName,
                fixture.proof.publicKeyHash
            );
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, MessageHashUtils.toEthSignedMessageHash(bytes(message)));
            ECDSAOwnedDKIMRegistry(address(_dkimRegistry)).setDKIMPublicKeyHash(
                _selector,
                fixture.proof.domainName,
                fixture.proof.publicKeyHash,
                abi.encodePacked(r, s, v)
            );
        }
    }

    function _boundPoints(
        uint256[2] memory pA,
        uint256[2][2] memory pB,
        uint256[2] memory pC
    ) private pure returns (uint256[2] memory, uint256[2][2] memory, uint256[2] memory) {
        pA[0] = bound(pA[0], 1, Q - 1);
        pA[1] = bound(pA[1], 1, Q - 1);
        pB[0][0] = bound(pB[0][0], 1, Q - 1);
        pB[0][1] = bound(pB[0][1], 1, Q - 1);
        pB[1][0] = bound(pB[1][0], 1, Q - 1);
        pB[1][1] = bound(pB[1][1], 1, Q - 1);
        pC[0] = bound(pC[0], 1, Q - 1);
        pC[1] = bound(pC[1], 1, Q - 1);
        return (pA, pB, pC);
    }
}
