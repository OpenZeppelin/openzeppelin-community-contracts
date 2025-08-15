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
    using ZKEmailUtils for EmailProof;

    IDKIMRegistry private _dkimRegistry;
    IGroth16Verifier private _verifier;
    bytes32 private _accountSalt;
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
        _mockProof = abi.encodePacked(bytes1(0x01));
    }

    function testFixtureCase1SignHash() public {
        EmailAuthMsg memory authMsg = EmailAuthMsgFixtures.getCase1();
        _setupDKIMRegistryForFixture(authMsg);
        ZKEmailUtils.EmailProofError err = authMsg.proof.isValidZKEmail(
            _dkimRegistry,
            _verifier,
            abi.decode(authMsg.commandParams[0], (bytes32))
        );
        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
    }

    function testFixtureCase2SignHash() public {
        EmailAuthMsg memory authMsg = EmailAuthMsgFixtures.getCase2();
        _setupDKIMRegistryForFixture(authMsg);
        ZKEmailUtils.EmailProofError err = authMsg.proof.isValidZKEmail(
            _dkimRegistry,
            _verifier,
            abi.decode(authMsg.commandParams[0], (bytes32))
        );
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
            authMsg.proof,
            _dkimRegistry,
            _verifier,
            template,
            authMsg.commandParams,
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
            authMsg.proof,
            _dkimRegistry,
            _verifier,
            template,
            authMsg.commandParams,
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

        // Build email proof with fuzzed parameters
        EmailProof memory emailProof = _buildEmailProofMock(string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()));

        // Override with fuzzed values
        emailProof.timestamp = timestamp;
        emailProof.emailNullifier = emailNullifier;
        emailProof.accountSalt = accountSalt;
        emailProof.isCodeExist = isCodeExist;
        emailProof.proof = proof;

        _mockVerifyEmailProof();

        // Test validation
        ZKEmailUtils.EmailProofError err = emailProof.isValidZKEmail(IDKIMRegistry(_dkimRegistry), _verifier, hash);

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

        EmailProof memory emailProof = _buildEmailProofMock(
            string.concat(commandPrefix, " ", uint256(hash).toString())
        );

        // Override with fuzzed values
        emailProof.timestamp = timestamp;
        emailProof.emailNullifier = emailNullifier;
        emailProof.accountSalt = accountSalt;
        emailProof.isCodeExist = isCodeExist;
        emailProof.proof = proof;

        string[] memory template = new string[](2);
        template[0] = commandPrefix;
        template[1] = CommandUtils.UINT_MATCHER;

        _mockVerifyEmailProof();

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailProof,
            IDKIMRegistry(_dkimRegistry),
            _verifier,
            template,
            commandParams
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
            EmailProof memory emailProof = _buildEmailProofMock(
                string.concat(commandPrefix, " ", CommandUtils.addressToHexString(addr, i))
            );

            // Override with fuzzed values
            emailProof.timestamp = timestamp;
            emailProof.emailNullifier = emailNullifier;
            emailProof.accountSalt = accountSalt;
            emailProof.isCodeExist = isCodeExist;
            emailProof.proof = proof;

            _mockVerifyEmailProof();

            string[] memory template = new string[](2);
            template[0] = commandPrefix;
            template[1] = CommandUtils.ETH_ADDR_MATCHER;

            ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
                emailProof,
                IDKIMRegistry(_dkimRegistry),
                _verifier,
                template,
                commandParams,
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

        EmailProof memory emailProof = _buildEmailProofMock(string.concat(commandPrefix, " ", addr.toHexString()));

        // Override with fuzzed values
        emailProof.timestamp = timestamp;
        emailProof.emailNullifier = emailNullifier;
        emailProof.accountSalt = accountSalt;
        emailProof.isCodeExist = isCodeExist;
        emailProof.proof = proof;

        string[] memory template = new string[](2);
        template[0] = commandPrefix;
        template[1] = CommandUtils.ETH_ADDR_MATCHER;

        _mockVerifyEmailProof();

        ZKEmailUtils.EmailProofError err = ZKEmailUtils.isValidZKEmail(
            emailProof,
            IDKIMRegistry(_dkimRegistry),
            _verifier,
            template,
            commandParams,
            ZKEmailUtils.Case.ANY
        );

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.NoError));
    }

    function testInvalidDKIMPublicKeyHash(bytes32 hash, string memory domainName, bytes32 publicKeyHash) public view {
        EmailProof memory emailProof = _buildEmailProofMock(string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()));

        emailProof.domainName = domainName;
        emailProof.publicKeyHash = publicKeyHash;

        ZKEmailUtils.EmailProofError err = emailProof.isValidZKEmail(IDKIMRegistry(_dkimRegistry), _verifier, hash);

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.DKIMPublicKeyHash));
    }

    function testInvalidMaskedCommandLength(bytes32 hash, uint256 length) public view {
        length = bound(length, 606, 1000); // Assuming commandBytes is 605

        EmailProof memory emailProof = _buildEmailProofMock(string(new bytes(length)));

        ZKEmailUtils.EmailProofError err = emailProof.isValidZKEmail(IDKIMRegistry(_dkimRegistry), _verifier, hash);

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.MaskedCommandLength));
    }

    function testMismatchedCommand(bytes32 hash, string memory invalidCommand) public view {
        EmailProof memory emailProof = _buildEmailProofMock(invalidCommand);

        ZKEmailUtils.EmailProofError err = emailProof.isValidZKEmail(IDKIMRegistry(_dkimRegistry), _verifier, hash);

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.MismatchedCommand));
    }

    function testInvalidEmailProof(
        bytes32 hash,
        uint256[2] memory pA,
        uint256[2][2] memory pB,
        uint256[2] memory pC
    ) public view {
        (pA, pB, pC) = _boundPoints(pA, pB, pC);

        EmailProof memory emailProof = _buildEmailProofMock(string.concat(SIGN_HASH_COMMAND, uint256(hash).toString()));

        emailProof.proof = abi.encode(pA, pB, pC);

        ZKEmailUtils.EmailProofError err = emailProof.isValidZKEmail(IDKIMRegistry(_dkimRegistry), _verifier, hash);

        assertEq(uint256(err), uint256(ZKEmailUtils.EmailProofError.EmailProof));
    }

    function testTryDecodeEmailProofValid(
        string memory domainName,
        bytes32 publicKeyHash,
        uint256 timestamp,
        string memory maskedCommand,
        bytes32 emailNullifier,
        bytes32 accountSalt,
        bool isCodeExist,
        bytes memory proof
    ) public view {
        (bool success, EmailProof memory emailProof) = this.tryDecodeEmailProof(
            abi.encode(
                domainName,
                publicKeyHash,
                timestamp,
                maskedCommand,
                emailNullifier,
                accountSalt,
                isCodeExist,
                proof
            )
        );
        assertTrue(success);
        assertEq(emailProof.domainName, domainName);
        assertEq(emailProof.publicKeyHash, publicKeyHash);
        assertEq(emailProof.timestamp, timestamp);
        assertEq(emailProof.maskedCommand, maskedCommand);
        assertEq(emailProof.emailNullifier, emailNullifier);
        assertEq(emailProof.accountSalt, accountSalt);
        assertEq(emailProof.isCodeExist, isCodeExist);
        assertEq(emailProof.proof, proof);
    }

    function testTryDecodeEmailProofInvalid() public view {
        string memory domainName = "gmail.com";
        bytes32 publicKeyHash = keccak256("publicKeyHash");
        uint256 timestamp = block.timestamp;
        string memory maskedCommand = "signHash 12345";
        bytes32 emailNullifier = keccak256("emailNullifier");
        bytes32 accountSalt = keccak256("accountSalt");
        bool isCodeExist = true;
        bytes memory proof = hex"deadbeef";

        // too short
        assertFalse(
            this.tryDecodeEmailProofDrop(abi.encodePacked(publicKeyHash, timestamp, emailNullifier, accountSalt))
        );

        // offset out of bound for domainName (position 0x00)
        bytes memory encoded = abi.encodePacked(
            abi.encodePacked(
                uint256(0x200), // domainName offset pointing outside
                publicKeyHash,
                timestamp,
                uint256(0x160), // maskedCommand offset
                emailNullifier,
                accountSalt,
                isCodeExist
            ),
            abi.encodePacked(
                uint256(0x180), // proof offset
                uint256(bytes(domainName).length),
                domainName,
                uint256(bytes(maskedCommand).length),
                maskedCommand,
                uint256(proof.length),
                proof
            )
        );
        assertFalse(this.tryDecodeEmailProofDrop(encoded));

        // offset out of bound for maskedCommand (position 0x60)
        encoded = abi.encodePacked(
            abi.encodePacked(
                uint256(0x100), // domainName offset
                publicKeyHash,
                timestamp,
                uint256(0x200), // maskedCommand offset pointing outside
                emailNullifier,
                accountSalt,
                isCodeExist
            ),
            abi.encodePacked(
                uint256(0x140), // proof offset
                uint256(bytes(domainName).length),
                domainName,
                uint256(bytes(maskedCommand).length),
                maskedCommand,
                uint256(proof.length),
                proof
            )
        );
        assertFalse(this.tryDecodeEmailProofDrop(encoded));

        // offset out of bound for proof (position 0xe0)
        encoded = abi.encodePacked(
            abi.encodePacked(
                uint256(0x100), // domainName offset
                publicKeyHash,
                timestamp,
                uint256(0x120), // maskedCommand offset
                emailNullifier,
                accountSalt,
                isCodeExist
            ),
            abi.encodePacked(
                uint256(0x200), // proof offset pointing outside
                uint256(bytes(domainName).length),
                domainName,
                uint256(bytes(maskedCommand).length),
                maskedCommand,
                uint256(proof.length),
                proof
            )
        );
        assertFalse(this.tryDecodeEmailProofDrop(encoded));

        // minimal valid (all dynamic fields length 0, at the same position)
        assertTrue(
            this.tryDecodeEmailProofDrop(
                abi.encodePacked(
                    uint256(0x100), // domainName offset
                    publicKeyHash,
                    timestamp,
                    uint256(0x100), // maskedCommand offset
                    emailNullifier,
                    accountSalt,
                    isCodeExist ? bytes32(uint256(1)) : bytes32(0),
                    uint256(0x100), // proof offset
                    uint256(0) // length 0 for all dynamic fields
                )
            )
        );

        // length out of bound for domainName
        assertTrue(
            this.tryDecodeEmailProofDrop(
                abi.encodePacked(
                    uint256(0x100), // domainName offset
                    publicKeyHash,
                    timestamp,
                    uint256(0x120), // maskedCommand offset
                    emailNullifier,
                    accountSalt,
                    isCodeExist ? bytes32(uint256(1)) : bytes32(0),
                    uint256(0x140), // proof offset
                    uint256(0x20), // domainName length 32 bytes
                    bytes32(0), // 32 bytes of domain data
                    uint256(0), // maskedCommand length 0
                    uint256(0) // proof length 0
                )
            )
        );

        // length pointing outside buffer for domainName
        assertFalse(
            this.tryDecodeEmailProofDrop(
                abi.encodePacked(
                    uint256(0x100), // domainName offset
                    publicKeyHash,
                    timestamp,
                    uint256(0x120), // maskedCommand offset
                    emailNullifier,
                    accountSalt,
                    isCodeExist ? bytes32(uint256(1)) : bytes32(0),
                    uint256(0x140), // proof offset
                    uint256(0x61), // domainName length 97 (32 * 3 + 1) bytes (too long for available data)
                    bytes32(0), // only 32 bytes of domain data
                    uint256(0), // maskedCommand length 0
                    uint256(0) // proof length 0
                )
            )
        );

        // valid case with proper offsets and lengths
        assertTrue(
            this.tryDecodeEmailProofDrop(
                abi.encodePacked(
                    uint256(0x100), // domainName offset
                    publicKeyHash,
                    timestamp,
                    uint256(0x120), // maskedCommand offset
                    emailNullifier,
                    accountSalt,
                    isCodeExist ? bytes32(uint256(1)) : bytes32(0),
                    uint256(0x140), // proof offset
                    uint256(0), // domainName length 0
                    uint256(0), // maskedCommand length 0
                    uint256(0) // proof length 0
                )
            )
        );

        // invalid case with length pointing outside for proof
        assertFalse(
            this.tryDecodeEmailProofDrop(
                abi.encodePacked(
                    uint256(0x100), // domainName offset
                    publicKeyHash,
                    timestamp,
                    uint256(0x120), // maskedCommand offset
                    emailNullifier,
                    accountSalt,
                    isCodeExist ? bytes32(uint256(1)) : bytes32(0),
                    uint256(0x140), // proof offset
                    uint256(0), // domainName length 0
                    uint256(0), // maskedCommand length 0
                    uint256(0x01) // proof length 1 (but no data provided)
                )
            )
        );
    }

    function tryDecodeEmailProof(
        bytes calldata encoded
    ) public pure returns (bool success, EmailProof calldata emailProof) {
        (success, emailProof) = ZKEmailUtils.tryDecodeEmailProof(encoded);
    }

    function tryDecodeEmailProofDrop(bytes calldata encoded) public pure returns (bool success) {
        (success, ) = ZKEmailUtils.tryDecodeEmailProof(encoded);
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

    function _mockVerifyEmailProof() private {
        vm.mockCall(
            address(_verifier),
            abi.encodeWithSelector(IGroth16Verifier.verifyProof.selector),
            abi.encode(true)
        );
    }

    function _buildEmailProofMock(string memory command) private view returns (EmailProof memory emailProof) {
        emailProof = EmailProof({
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
        uint256 Q = ZKEmailUtils.Q;
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
