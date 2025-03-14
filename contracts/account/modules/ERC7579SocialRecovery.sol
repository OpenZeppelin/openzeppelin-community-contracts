// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC7579Module, MODULE_TYPE_EXECUTOR, MODULE_TYPE_FALLBACK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {EnumerableMapExtended} from "../../utils/structs/EnumerableMapExtended.sol";
import {Permission, ThresholdConfig, RecoveryConfigArg, IPermissionVerifier, IRecoveryPolicyVerifier, ISocialRecovery} from "./ISocialRecovery.sol";

abstract contract ERC7579SocialRecovery is EIP712, Nonces, IERC7579Module, ISocialRecovery, IRecoveryPolicyVerifier {
    using Checkpoints for *;
    using EnumerableMapExtended for *;
    using SafeCast for *;

    bytes32 private constant START_RECOVERY_TYPEHASH =
        keccak256("StartRecovery(address account,bytes recovery,uint256 nonce)");
    bytes32 private constant CANCEL_RECOVERY_TYPEHASH =
        keccak256("CancelRecovery(address account,bytes recovery,uint256 nonce)");

    struct AccountConfig {
        address verifier;
        EnumerableMapExtended.BytesToUintMap guardians;
        Checkpoints.Trace160 thresholds;
        bytes recoveryCall;
        uint48 expiryTime;
    }

    mapping(address account => AccountConfig) private _configs;

    event RecoveryConfigCleared(address indexed account, RecoveryConfigArg recoveryConfigArgs);
    event RecoveryConfigCleared(address indexed account);
    event RecoveryStarted(address indexed account, bytes recoveryCall, uint48 expiryTime);
    event RecoveryExecuted(address indexed account, bytes recoveryCall);
    event RecoveryCanceled(address indexed account);
    error InvalidGuardian(address account, bytes identity);
    error InvalidSignature(address account, bytes identity);
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
            // uniqueness
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
        _overrideConfig(msg.sender, recoveryConfigArg);
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
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        CANCEL_RECOVERY_TYPEHASH,
                        account,
                        keccak256(_configs[account].recoveryCall),
                        _useNonce(account)
                    )
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
        (bool exist_, uint256 property_) = _configs[account].guardians.tryGet(guardian);
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
            (bytes memory identity, uint256 property) = config.guardians.at(i);
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
    function _overrideConfig(address account, RecoveryConfigArg calldata recoveryConfigArgs) internal virtual {
        _clearConfig(account);

        AccountConfig storage config = _configs[account];

        // verifier
        config.verifier = recoveryConfigArgs.verifier == address(0) ? address(this) : recoveryConfigArgs.verifier;

        // guardians
        for (uint256 i = 0; i < recoveryConfigArgs.guardians.length; ++i) {
            (uint64 property, bytes calldata identity) = _parseGuardian(recoveryConfigArgs.guardians[i]);
            config.guardians.set(identity, property);
        }

        // threshold
        for (uint256 i = 0; i < recoveryConfigArgs.thresholds.length; ++i) {
            config.thresholds.push(
                recoveryConfigArgs.thresholds[i].threshold,
                recoveryConfigArgs.thresholds[i].lockPeriod
            );
        }

        emit RecoveryConfigCleared(account, recoveryConfigArgs);
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
        delete config.verifier;
        delete config.recoveryCall;
        delete config.expiryTime;

        emit RecoveryConfigCleared(account);
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
            bool validIdentity;
            (validIdentity, properties[i]) = isGuardian(account, permissions[i].identity);
            require(validIdentity, InvalidGuardian(account, permissions[i].identity));
            require(
                _verifyIdentitySignature(permissions[i].identity, hash, permissions[i].signature),
                InvalidSignature(account, permissions[i].identity)
            );
        }

        // verify recovery policy
        (bool success, uint64 weight) = IRecoveryPolicyVerifier(config.verifier).verifyRecoveryPolicy(
            account,
            permissions,
            properties
        );
        require(success, PolicyVerificationFailed(account));

        // get lock period
        uint48 lockPeriod = config.thresholds.upperLookup(weight).toUint48(); // uint160 -> uint48

        // TODO: case where the delay really is zero vs case where there is no delay?
        require(lockPeriod > 0, ThresholdNotReached(account, weight));

        return lockPeriod;
    }

    function _startRecovery(
        address account,
        bytes calldata recoveryCall,
        uint48 lockPeriod
    ) internal virtual onlyNotRecovering(account) {
        uint48 expiryTime = SafeCast.toUint48(block.timestamp + lockPeriod);

        // set recovery details
        _configs[account].recoveryCall = recoveryCall;
        _configs[account].expiryTime = expiryTime;

        emit RecoveryStarted(account, recoveryCall, expiryTime);
    }

    function _executeRecovery(address account) internal virtual onlyRecoveryReady(account) {
        // cache
        bytes memory recoveryCall = _configs[account].recoveryCall;

        // clean (prevents reentry)
        delete _configs[account].recoveryCall;
        delete _configs[account].expiryTime;

        // perform call
        Address.functionCall(account, recoveryCall);

        emit RecoveryExecuted(account, recoveryCall);
    }

    function _cancelRecovery(address account) internal virtual onlyRecovering(account) {
        // clean
        delete _configs[account].recoveryCall;
        delete _configs[account].expiryTime;

        emit RecoveryCanceled(account);
    }

    /****************************************************************************************************************
     *                                                   Helpers                                                    *
     ****************************************************************************************************************/
    function _formatGuardian(
        uint64 property,
        bytes memory identity
    ) internal pure virtual returns (bytes memory guardian) {
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
