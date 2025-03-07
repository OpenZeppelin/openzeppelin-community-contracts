// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// Identity = [ verifyingContract (address) || signer (bytes) ]
// type Identity = bytes;

/// Guardian = [ property (uint64) | Identity (bytes) ] = [ property (uint64) || verifyingContract (address) || signer (bytes) ]
// type Guardian = bytes;

struct Permission {
    bytes identity;
    bytes signature;
}

struct ThresholdConfig {
    uint64 threshold; // Threshold value
    uint48 lockPeriod; // Lock period for the threshold
}

struct RecoveryConfigArg {
    address verifier;
    bytes[] guardians;
    ThresholdConfig[] thresholds;
}

interface IPermissionVerifier {
    /// @dev Check if the signer key format is correct
    function isValidSigner(bytes calldata signer) external view returns (bool);

    /// @dev Validate signature for a given signer
    function isValidPermission(
        bytes32 hash,
        bytes calldata signer,
        bytes calldata signature
    ) external view returns (bool);
}

interface IRecoveryPolicyVerifier {
    function verifyRecoveryPolicy(
        address account,
        Permission[] calldata permissions,
        uint64[] calldata properties
    ) external view returns (bool succ, uint64 weight);
}

interface ISocialRecoveryModule {
    function updateGuardians(RecoveryConfigArg calldata recoveryConfigArg) external;

    function startRecovery(bytes calldata recoveryCall, Permission[] calldata permissions) external;

    function startRecovery(address account, bytes calldata recoveryCall, Permission[] calldata permissions) external;

    function executeRecovery() external;

    function executeRecovery(address account) external;

    function cancelRecovery() external;

    function cancelRecoveryByGuardians(Permission[] calldata permissions) external;

    function cancelRecoveryByGuardians(address account, Permission[] calldata permissions) external;

    function isGuardian(bytes calldata guardian) external view returns (bool exist, uint64 property);

    function isGuardian(address account, bytes calldata guardian) external view returns (bool exist, uint64 property);

    function getAccountConfigs() external view returns (RecoveryConfigArg memory recoveryConfigArg);

    function getAccountConfigs(address account) external view returns (RecoveryConfigArg memory recoveryConfigArg);

    function getRecoveryStatus() external view returns (bool isRecovering, uint48 expiryTime);

    function getRecoveryStatus(address account) external view returns (bool isRecovering, uint48 expiryTime);
}
