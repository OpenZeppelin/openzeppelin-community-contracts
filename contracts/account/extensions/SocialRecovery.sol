// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC7579Module, MODULE_TYPE_EXECUTOR, MODULE_TYPE_FALLBACK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

import {Permission, ThresholdConfig, RecoveryConfigArg, IPermissionVerifier, IRecoveryPolicyVerifier, ISocialRecoveryModule} from "./ISocialRecovery.sol";

contract SocialRecoveryModule is EIP712("SocialRecovery", "1"), Nonces, IERC7579Module, IRecoveryPolicyVerifier {
    using Checkpoints for *;
    using EnumerableMap for *;
    using SafeCast for *;

    bytes32 private constant START_RECOVERY_TYPEHASH =
        keccak256("StartRecovery(address account, bytes recovery, uint256 nonce)");
    bytes32 private constant CANCEL_RECOVERY_TYPEHASH =
        keccak256("CancelRecovery(address account, bytes recovery, uint256 nonce)");

    struct AccountConfig {
        address verifier;
        // EnumerableMap.BytesToUintMap guardians;
        EnumerableMap.Bytes32ToUintMap guardians;
        Checkpoints.Trace160 thresholds;
        bytes recoveryCall;
        uint48 expiryTime;
    }

    mapping(address account => AccountConfig) private _configs;

    modifier onlyNotRecovering(address account) {
        require(_configs[account].expiryTime == 0, "recovering");
        _;
    }

    modifier onlyRecovering(address account) {
        require(_configs[account].expiryTime != 0, "not recovering");
        _;
    }

    modifier onlyRecoveryReady(address account) {
        uint48 expiryTime = _configs[account].expiryTime;
        require(expiryTime != 0 && expiryTime <= block.timestamp, "not recovering");
        _;
    }

    /****************************************************************************************************************
     *                                                IERC7579Module                                                *
     ****************************************************************************************************************/
    function onInstall(bytes calldata data) public virtual {}

    function onUninstall(bytes calldata data) public virtual {}

    function isModuleType(uint256 moduleTypeId) public view virtual returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR || moduleTypeId == MODULE_TYPE_FALLBACK;
    }

    /****************************************************************************************************************
     *                                  Social recovery - IRecoveryPolicyVerifier                                   *
     ****************************************************************************************************************/
    function verifyRecoveryPolicy(
        address,
        Permission[] calldata permissions,
        uint64[] calldata properties
    ) public view virtual returns (bool success, uint64 weight) {
        if (permissions.length != properties.length) return (false, 0);

        success = true;
        weight = 0;

        bytes32 previousHash = bytes32(0);
        for (uint256 i = 0; i < permissions.length; ++i) {
            // unicity
            bytes32 newHash = keccak256(permissions[i].identity);
            if (newHash <= previousHash) return (false, 0);
            previousHash = newHash;
            // total weight
            weight += properties[i];
        }
    }

    /****************************************************************************************************************
     *                                            Social recovery - Core                                            *
     ****************************************************************************************************************/
    function updateGuardians(RecoveryConfigArg calldata recoveryConfigArg) public virtual {
        _updateGuardians(msg.sender, recoveryConfigArg);
    }

    function startRecovery(bytes calldata recoveryCall, Permission[] calldata permissions) external {
        startRecovery(msg.sender, recoveryCall, permissions);
    }

    function startRecovery(
        address account,
        bytes calldata recoveryCall,
        Permission[] calldata permissions
    ) public virtual {
        uint48 lockPeriod = _checkPermissions(
            account,
            _hashTypedDataV4(keccak256(abi.encode(START_RECOVERY_TYPEHASH, account, recoveryCall, _useNonce(account)))),
            permissions
        );
        _startRecovery(account, recoveryCall, lockPeriod);
    }

    function executeRecovery() external {
        executeRecovery(msg.sender);
    }

    function executeRecovery(address account) public virtual {
        _executeRecovery(account);
    }

    function cancelRecovery() public virtual {
        _cancelRecovery(msg.sender);
    }

    function cancelRecoveryByGuardians(Permission[] calldata permissions) external {
        cancelRecoveryByGuardians(msg.sender, permissions);
    }

    function cancelRecoveryByGuardians(address account, Permission[] calldata permissions) public virtual {
        _checkPermissions(
            account,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(CANCEL_RECOVERY_TYPEHASH, account, _configs[account].recoveryCall, _useNonce(account))
                )
            ),
            permissions
        );
        _cancelRecovery(account);
    }

    function isGuardian(bytes calldata guardian) external view returns (bool exist, uint64 property) {
        return isGuardian(msg.sender, guardian);
    }

    function isGuardian(
        address account,
        bytes calldata guardian
    ) public view virtual returns (bool exist, uint64 property) {
        (bool exist_, uint256 property_) = _configs[account].guardians.tryGet(bytes32(guardian));
        return (exist_, property_.toUint48());
    }

    function getAccountConfigs() external view returns (RecoveryConfigArg memory recoveryConfigArg) {
        return getAccountConfigs(msg.sender);
    }

    function getAccountConfigs(
        address account
    ) public view virtual returns (RecoveryConfigArg memory recoveryConfigArg) {
        AccountConfig storage config = _configs[account];

        bytes[] memory guardians = new bytes[](config.guardians.length());
        for (uint256 i = 0; i < guardians.length; ++i) {
            (bytes32 identity, uint256 property) = config.guardians.at(i);
            guardians[i] = _formatGuardian(property.toUint64(), identity);
        }

        ThresholdConfig[] memory thresholds = new ThresholdConfig[](config.thresholds.length());
        for (uint256 i = 0; i < thresholds.length; ++i) {
            Checkpoints.Checkpoint160 memory ckpt = config.thresholds.at(i.toUint32());
            thresholds[i].threshold = ckpt._key.toUint64();
            thresholds[i].lockPeriod = ckpt._value.toUint48();
        }

        return RecoveryConfigArg({verifier: config.verifier, guardians: guardians, thresholds: thresholds});
    }

    function getRecoveryNonce() external view returns (uint256 nonce) {
        return nonces(msg.sender);
    }

    function getRecoveryStatus() external view returns (bool isRecovering, uint48 expiryTime) {
        return getRecoveryStatus(msg.sender);
    }

    function getRecoveryStatus(address account) public view virtual returns (bool isRecovering, uint48 expiryTime) {
        expiryTime = _configs[account].expiryTime;
        isRecovering = expiryTime != 0;
    }

    /****************************************************************************************************************
     *                                          Social recovery - internal                                          *
     ****************************************************************************************************************/
    function _updateGuardians(address account, RecoveryConfigArg calldata recoveryConfigArgs) internal virtual {
        AccountConfig storage config = _configs[account];

        // verifier
        config.verifier = recoveryConfigArgs.verifier == address(0) ? address(this) : recoveryConfigArgs.verifier;

        // guardians
        config.guardians.clear();
        for (uint256 i = 0; i < recoveryConfigArgs.guardians.length; ++i) {
            (uint64 property, bytes calldata identity) = _parseGuardian(recoveryConfigArgs.guardians[i]);
            config.guardians.set(bytes32(identity), property);
        }

        // threshold
        Checkpoints.Checkpoint160[] storage ckpts = config.thresholds._checkpoints;
        assembly ("memory-safe") {
            sstore(ckpts.slot, 0)
        }
        for (uint256 i = 0; i < recoveryConfigArgs.thresholds.length; ++i) {
            config.thresholds.push(
                recoveryConfigArgs.thresholds[i].threshold,
                recoveryConfigArgs.thresholds[i].lockPeriod
            );
        }

        // TODO emit event
    }

    function _checkPermissions(
        address account,
        bytes32 hash,
        Permission[] calldata permissions
    ) internal virtual returns (uint48) {
        AccountConfig storage config = _configs[account];

        // verify signature and get properties
        uint64[] memory properties = new uint64[](permissions.length);
        for (uint256 i = 0; i < permissions.length; ++i) {
            require(config.guardians.contains(bytes32(permissions[i].identity)), "invalid guardian");
            require(
                _verifyIdentitySignature(permissions[i].identity, hash, permissions[i].signature),
                "InvalidSignature"
            );
            properties[i] = config.guardians.get(bytes32(permissions[i].identity)).toUint64();
        }

        // verify recovery policy
        (bool success, uint64 weight) = IRecoveryPolicyVerifier(config.verifier).verifyRecoveryPolicy(
            account,
            permissions,
            properties
        );
        require(success);

        // get lock period
        uint48 lockPeriod = config.thresholds.upperLookup(weight).toUint48(); // uint160 -> uint48
        require(lockPeriod > 0); // TODO: case where the delay is zero ?

        return lockPeriod;
    }

    function _startRecovery(
        address account,
        bytes calldata recoveryCall,
        uint48 lockPeriod
    ) internal virtual onlyNotRecovering(account) {
        // set recovery details
        _configs[account].recoveryCall = recoveryCall;
        _configs[account].expiryTime = SafeCast.toUint48(block.timestamp + lockPeriod);

        // TODO emit event
    }

    function _executeRecovery(address account) internal virtual onlyRecoveryReady(account) {
        // cache
        bytes memory recoveryCall = _configs[account].recoveryCall;

        // clean (prevents reentry)
        delete _configs[account].recoveryCall;
        delete _configs[account].expiryTime;

        // perform call
        Address.functionCall(account, recoveryCall);

        // TODO emit event
    }

    function _cancelRecovery(address account) internal virtual onlyRecovering(account) {
        // clean
        delete _configs[account].recoveryCall;
        delete _configs[account].expiryTime;

        // TODO emit event
    }

    /****************************************************************************************************************
     *                                                   Helpers                                                    *
     ****************************************************************************************************************/
    function _formatGuardian(uint64 property, bytes32 identity) internal pure virtual returns (bytes memory guardian) {
        return abi.encodePacked(property, identity);
    }

    function _parseGuardian(
        bytes calldata guardian
    ) internal pure virtual returns (uint64 property, bytes calldata identity) {
        property = uint64(bytes8(guardian[0:8]));
        identity = guardian[8:];
    }

    function _parseIdentity(
        bytes calldata identity
    ) internal pure virtual returns (address verifyingContract, bytes calldata signer) {
        verifyingContract = address(bytes20(identity[0:20]));
        signer = identity[20:];
    }

    function _verifyIdentitySignature(
        bytes calldata identity,
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual returns (bool) {
        (address verifyingContract, bytes calldata signer) = _parseIdentity(identity);
        return
            (signer.length == 0)
                ? SignatureChecker.isValidSignatureNow(verifyingContract, hash, signature)
                : IPermissionVerifier(verifyingContract).isValidPermission(hash, signer, signature);
    }
}
