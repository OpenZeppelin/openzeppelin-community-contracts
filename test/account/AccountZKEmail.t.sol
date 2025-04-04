// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AccountZKEmailMock} from "../../contracts/mocks/account/AccountZKEmailMock.sol";
import {SignerZKEmail, IDKIMRegistry, IVerifier, EmailAuthMsg, EmailProof} from "../../contracts/utils/cryptography/SignerZKEmail.sol";
import {CallReceiverMockExtended} from "../../contracts/mocks/CallReceiverMock.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract AccountZKEmailTest is Test {
    using Strings for string;

    AccountZKEmailMock private _account;
    CallReceiverMockExtended private _target;
    IDKIMRegistry private _dkimRegistry;
    IVerifier private _verifier;
    bytes32 private _accountSalt;
    uint256 private _templateId;
    bytes32 private _publicKeyHash;
    bytes32 private _emailNullifier;
    bytes private _mockProof;

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

        // Deploy account
        _account = new AccountZKEmailMock(_accountSalt, _dkimRegistry, _verifier, _templateId);

        // Deploy target
        _target = new CallReceiverMockExtended();
    }

    function buildEmailAuthMsg(bytes32 hash) public returns (EmailAuthMsg memory emailAuthMsg) {
        bytes[] memory commandParams = new bytes[](1);
        commandParams[0] = abi.encode(hash);

        EmailProof memory emailProof = EmailProof({
            domainName: "gmail.com",
            publicKeyHash: _publicKeyHash,
            timestamp: block.timestamp,
            maskedCommand: string.concat("signHash ", Strings.toString(uint256(hash))),
            emailNullifier: _emailNullifier,
            accountSalt: _accountSalt,
            isCodeExist: true,
            proof: _mockProof
        });

        emailAuthMsg = EmailAuthMsg({
            templateId: _templateId,
            commandParams: commandParams,
            skippedCommandPrefix: 0,
            proof: emailProof
        });

        // Setup mock verifier
        MockVerifier(address(_verifier)).setCommandBytes(1000);
        MockDKIMRegistry(address(_dkimRegistry)).setValidPublicKeyHash("gmail.com", _publicKeyHash);
    }

    function testVerifyEmail(bytes32 hash) public {
        EmailAuthMsg memory emailAuthMsg = buildEmailAuthMsg(hash);
        _account.verifyEmail(emailAuthMsg);
    }
}

// Mock DKIM Registry for testing
contract MockDKIMRegistry is IDKIMRegistry {
    mapping(string => bytes32) private _validPublicKeyHashes;

    function setValidPublicKeyHash(string memory domainName, bytes32 publicKeyHash) public {
        _validPublicKeyHashes[domainName] = publicKeyHash;
    }

    function isDKIMPublicKeyHashValid(string memory domainName, bytes32 publicKeyHash) external view returns (bool) {
        return _validPublicKeyHashes[domainName] == publicKeyHash;
    }
}

// Mock Verifier for testing
contract MockVerifier is IVerifier {
    uint256 private _commandBytes;

    function setCommandBytes(uint256 commandBytes_) public {
        _commandBytes = commandBytes_;
    }

    function commandBytes() external view returns (uint256) {
        return _commandBytes;
    }

    function verifyEmailProof(EmailProof memory /* proof */) external pure returns (bool) {
        return true; // Always return true for testing
    }
}
