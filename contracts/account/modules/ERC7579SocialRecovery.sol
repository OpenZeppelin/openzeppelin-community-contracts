// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC7579Module, MODULE_TYPE_EXECUTOR, MODULE_TYPE_FALLBACK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {ERC7913Utils} from "../../utils/cryptography/ERC7913Utils.sol";
import {EnumerableMapExtended} from "../../utils/structs/EnumerableMapExtended.sol";

abstract contract ERC7579SocialRecovery is EIP712, Nonces, IERC7579Module {
    using Checkpoints for *;
    using EnumerableMapExtended for *;
    using SafeCast for *;

    bytes32 private constant START_RECOVERY_TYPEHASH =
        keccak256("StartRecovery(address account,bytes recovery,uint256 nonce)");
    bytes32 private constant CANCEL_RECOVERY_TYPEHASH = keccak256("CancelRecovery(address account,uint256 nonce)");

    struct Permission {
        bytes signer;
        bytes signature;
    }

    struct ThresholdConfig {
        uint64 threshold; // Threshold value
        uint48 lockPeriod; // Lock period for the threshold
    }

    struct AccountConfig {
        EnumerableMapExtended.BytesToUintMap guardians;
        Checkpoints.Trace160 thresholds;
        uint48 expiryTime;
        bytes recoveryCall;
    }

    mapping(address account => AccountConfig) private _configs;

    event RecoveryConfigSet(address indexed account, bytes[] guardians, ThresholdConfig[] thresholds);
    event RecoveryConfigCleared(address indexed account);
    event RecoveryStarted(address indexed account, bytes recoveryCall, uint48 expiryTime);
    event RecoveryExecuted(address indexed account, bytes recoveryCall);
    event RecoveryCanceled(address indexed account);
    error InvalidGuardian(address account, bytes signer);
    error InvalidSignature(address account, bytes signer);
    error PolicyVerificationFailed(address account);
    error ThresholdNotReached(address account, uint64 weight);
    error AccountNotInRecovery(address account);
    error AccountRecoveryPending(address account);
    error AccountRecoveryNotReady(address account);

    modifier onlyNotRecovering(address account) {
        require(_configs[account].expiryTime == 0, AccountRecoveryPending(account));
        _;
    }

    modifier onlyRecovering(address account) {
        require(_configs[account].expiryTime != 0, AccountNotInRecovery(account));
        _;
    }

    modifier onlyRecoveryReady(address account) {
        uint48 expiryTime = _configs[account].expiryTime;
        require(expiryTime != 0 && expiryTime <= block.timestamp, AccountRecoveryNotReady(account));
        _;
    }

    /****************************************************************************************************************
     *                                                IERC7579Module                                                *
     ****************************************************************************************************************/
    function onInstall(bytes calldata data) public virtual {
        if (data.length > 0) {
            Address.functionDelegateCall(address(this), data);
        }
    }

    function onUninstall(bytes calldata /*data*/) public virtual {
        _clearConfig(msg.sender);
    }

    function isModuleType(uint256 moduleTypeId) public view virtual returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR || moduleTypeId == MODULE_TYPE_FALLBACK;
    }

    /****************************************************************************************************************
     *                                            Social recovery - Core                                            *
     ****************************************************************************************************************/
    function updateGuardians(bytes[] calldata guardians, ThresholdConfig[] calldata thresholds) public virtual {
        _overrideConfig(msg.sender, guardians, thresholds);
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
            _hashTypedDataV4(
                keccak256(abi.encode(START_RECOVERY_TYPEHASH, account, keccak256(recoveryCall), _useNonce(account)))
            ),
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
            _hashTypedDataV4(keccak256(abi.encode(CANCEL_RECOVERY_TYPEHASH, account, _useNonce(account)))),
            permissions
        );
        _cancelRecovery(account);
    }

    function isGuardian(bytes calldata guardian) external view returns (bool exist, uint64 weight) {
        return isGuardian(msg.sender, guardian);
    }

    function isGuardian(
        address account,
        bytes calldata guardian
    ) public view virtual returns (bool exist, uint64 weight) {
        (bool exist_, uint256 weight_) = _configs[account].guardians.tryGet(guardian);
        return (exist_, weight_.toUint48());
    }

    function getAccountConfigs() external view returns (bytes[] memory guardians, ThresholdConfig[] memory thresholds) {
        return getAccountConfigs(msg.sender);
    }

    function getAccountConfigs(
        address account
    ) public view virtual returns (bytes[] memory guardians, ThresholdConfig[] memory thresholds) {
        AccountConfig storage config = _configs[account];

        guardians = new bytes[](config.guardians.length());
        for (uint256 i = 0; i < guardians.length; ++i) {
            (bytes memory signer, uint256 weight) = config.guardians.at(i);
            guardians[i] = _formatGuardian(weight.toUint64(), signer);
        }

        thresholds = new ThresholdConfig[](config.thresholds.length());
        for (uint256 i = 0; i < thresholds.length; ++i) {
            Checkpoints.Checkpoint160 memory ckpt = config.thresholds.at(i.toUint32());
            thresholds[i].threshold = ckpt._key.toUint64();
            thresholds[i].lockPeriod = ckpt._value.toUint48();
        }
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
    function _overrideConfig(
        address account,
        bytes[] calldata guardians,
        ThresholdConfig[] calldata thresholds
    ) internal virtual {
        _clearConfig(account);

        AccountConfig storage config = _configs[account];

        // guardians
        for (uint256 i = 0; i < guardians.length; ++i) {
            (uint64 weight, bytes calldata signer) = _parseGuardian(guardians[i]);
            config.guardians.set(signer, weight);
        }

        // threshold
        for (uint256 i = 0; i < thresholds.length; ++i) {
            config.thresholds.push(thresholds[i].threshold, thresholds[i].lockPeriod);
        }

        emit RecoveryConfigSet(account, guardians, thresholds);
    }

    function _clearConfig(address account) internal virtual {
        AccountConfig storage config = _configs[account];

        // clear enumerable map
        config.guardians.clear();

        // clear threshold
        Checkpoints.Checkpoint160[] storage ckpts = config.thresholds._checkpoints;
        assembly ("memory-safe") {
            sstore(ckpts.slot, 0)
        }

        // clear remaining
        delete config.expiryTime;
        delete config.recoveryCall;

        emit RecoveryConfigCleared(account);
    }

    function _checkPermissions(
        address account,
        bytes32 hash,
        Permission[] calldata permissions
    ) internal virtual returns (uint48) {
        AccountConfig storage config = _configs[account];

        // verify signature and get properties
        uint64 totalWeight = 0;
        bytes32 previousHash = bytes32(0);
        for (uint256 i = 0; i < permissions.length; ++i) {
            // uniqueness
            bytes32 newHash = keccak256(permissions[i].signer);
            require(previousHash < newHash, PolicyVerificationFailed(account));
            previousHash = newHash;

            // validity of signer and signature
            (bool validIdentity, uint64 weight) = isGuardian(account, permissions[i].signer);
            require(validIdentity, InvalidGuardian(account, permissions[i].signer));
            require(
                ERC7913Utils.isValidSignatureNow(permissions[i].signer, hash, permissions[i].signature),
                InvalidSignature(account, permissions[i].signer)
            );

            // total weight
            totalWeight += weight;
        }

        // get lock period
        uint48 lockPeriod = config.thresholds.upperLookup(totalWeight).toUint48(); // uint160 -> uint48

        // TODO: case where the delay really is zero vs case where there is no delay?
        require(lockPeriod > 0, ThresholdNotReached(account, totalWeight));

        return lockPeriod;
    }

    function _startRecovery(
        address account,
        bytes calldata recoveryCall,
        uint48 lockPeriod
    ) internal virtual onlyNotRecovering(account) {
        uint48 expiryTime = SafeCast.toUint48(block.timestamp + lockPeriod);

        // set recovery details
        _configs[account].expiryTime = expiryTime;
        _configs[account].recoveryCall = recoveryCall;

        emit RecoveryStarted(account, recoveryCall, expiryTime);
    }

    function _executeRecovery(address account) internal virtual onlyRecoveryReady(account) {
        // cache
        bytes memory recoveryCall = _configs[account].recoveryCall;

        // clean (prevents reentry)
        delete _configs[account].expiryTime;
        delete _configs[account].recoveryCall;

        // perform call
        Address.functionCall(account, recoveryCall);

        emit RecoveryExecuted(account, recoveryCall);
    }

    function _cancelRecovery(address account) internal virtual onlyRecovering(account) {
        // clean
        delete _configs[account].expiryTime;
        delete _configs[account].recoveryCall;

        emit RecoveryCanceled(account);
    }

    /****************************************************************************************************************
     *                                                   Helpers                                                    *
     ****************************************************************************************************************/
    function _formatGuardian(uint64 weight, bytes memory signer) internal pure virtual returns (bytes memory guardian) {
        return abi.encodePacked(weight, signer);
    }

    function _parseGuardian(
        bytes calldata guardian
    ) internal pure virtual returns (uint64 weight, bytes calldata signer) {
        weight = uint64(bytes8(guardian[0:8]));
        signer = guardian[8:];
    }
}
