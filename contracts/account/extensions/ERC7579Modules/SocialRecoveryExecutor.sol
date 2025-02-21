// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7579Module, IERC7579ModuleConfig, MODULE_TYPE_EXECUTOR, MODULE_TYPE_VALIDATOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {ERC7579Utils, Mode, CallType, ModeSelector, ExecType, ModePayload} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {AccountERC7579} from "../AccountERC7579.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Implements a Social Recovery Executor module following ERC-7579
 *
 * @dev Features:
 * - Timelocked Guardian-based recovery
 * - Recovery Execution Scope is limited to reconfiguring installed Validator Modules
 * - Recovery Reconfiguration can only be performed by the ERC-7579 Account
 * - Guardian Signatures replay attack protection via EIP-712 typed data signing
 * - Replay Attack protection includes: chains, accounts, executors, and recovery attempts
 */
contract SocialRecoveryExecutor is IERC7579Module, EIP712, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 private constant RECOVERY_TYPEHASH = keccak256("RecoveryMessage(address account,uint256 nonce)");

    /*//////////////////////////////////////////////////////////////////////////
                                EVENTS & ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    event ModuleUninstalledReceived(address indexed account, bytes data);
    event ModuleInstalledReceived(address indexed account, bytes data);

    event RecoveryExecuted(address indexed account, address indexed targetValidatorModule);
    event RecoveryCancelled(address indexed account);
    event RecoveryStarted(address indexed account);

    event ThresholdChanged(address indexed account, uint256 indexed threshold);
    event TimelockChanged(address indexed account, uint256 indexed timelock);
    event GuardianRemoved(address indexed account, address indexed guardian);
    event GuardianAdded(address indexed account, address indexed guardian);

    error InvalidTimelock();
    error InvalidThreshold();
    error InvalidGuardians();
    error InvalidGuardian();

    error CannotRemoveGuardian();
    error GuardianNotFound();
    error AlreadyGuardian();
    error MaxGuardians();

    error InvalidInstalledValidatorModule();
    error InvalidGuardianSignatures();
    error InvalidRecoveryCallData();

    error InvalidCallType();
    error ThresholdNotMet();

    error RecoveryAlreadyStarted();
    error RecoveryNotStarted();
    error RecoveryNotReady();

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANTS & STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    string public constant NAME = "SocialRecoveryExecutor";
    string public constant VERSION = "0.0.1";
    uint8 public constant MAX_GUARDIANS = 32;

    enum RecoveryStatus {
        NotStarted,
        Timelock,
        Ready
    }

    struct RecoveryConfig {
        EnumerableSet.AddressSet guardians;
        uint256 threshold;
        uint256 timelock;
        uint256 recoveryStart;
        uint256 nonce;
    }

    struct GuardianSignature {
        address signer;
        bytes signature;
    }

    mapping(address account => RecoveryConfig recoveryConfig) private _recoveryConfigs;

    /*///////////////////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    modifier whenRecoveryIsNotStarted(address account) {
        if (getRecoveryStatus(account) != RecoveryStatus.NotStarted) {
            revert RecoveryAlreadyStarted();
        }
        _;
    }

    modifier whenRecoveryIsReady(address account) {
        if (getRecoveryStatus(account) != RecoveryStatus.Ready) {
            revert RecoveryNotReady();
        }
        _;
    }

    modifier whenRecoveryIsTimelockOrReady(address account) {
        if (getRecoveryStatus(account) == RecoveryStatus.NotStarted) {
            revert RecoveryNotStarted();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONFIGURATION
    //////////////////////////////////////////////////////////////////////////*/

    constructor() EIP712(NAME, VERSION) {}

    /// @notice Initializes the module with guardian configuration
    /// @dev Called by the ERC-7579 Account during module installation
    /// @param data ABI encoded (address[] guardians, uint256 threshold, uint256 timelock)
    function onInstall(bytes calldata data) external override {
        address account = msg.sender;

        // decode the configuration.
        (address[] memory _guardians, uint256 _threshold, uint256 _timelock) = abi.decode(
            data,
            (address[], uint256, uint256)
        );

        // configuration must be valid.
        if (_guardians.length == 0) {
            revert InvalidGuardians();
        }
        if (_guardians.length > MAX_GUARDIANS) {
            revert MaxGuardians();
        }
        if (_threshold == 0 || _threshold > _guardians.length) {
            revert InvalidThreshold();
        }
        if (_timelock == 0) {
            revert InvalidTimelock();
        }

        for (uint256 i = 0; i < _guardians.length; i++) {
            if (_guardians[i] == address(0)) {
                revert InvalidGuardian();
            }
            bool added = _recoveryConfigs[account].guardians.add(_guardians[i]);
            if (!added) {
                revert InvalidGuardians();
            }
        }

        _recoveryConfigs[account].threshold = _threshold;
        _recoveryConfigs[account].timelock = _timelock;
        _recoveryConfigs[account].recoveryStart = 0;
        _recoveryConfigs[account].nonce = 0;

        emit ModuleInstalledReceived(account, data);
    }

    /// @notice De-initializes the module, clearing all guardian configuration
    /// @dev Called by the ERC-7579 Account during module uninstallation
    /// @param data Additional data (unused)
    function onUninstall(bytes calldata data) external override {
        address account = msg.sender;

        // Clear the guardians EnumerableSet
        address[] memory guardians = _recoveryConfigs[account].guardians.values();
        for (uint256 i = 0; i < guardians.length; i++) {
            _recoveryConfigs[account].guardians.remove(guardians[i]);
        }

        // clear the recovery config
        // slither-disable-next-line mapping-deletion
        delete _recoveryConfigs[account];

        emit ModuleUninstalledReceived(account, data);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MODULE MAIN LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Starts the recovery process for an account
    /// @dev Requires threshold number of valid guardian signatures
    /// @param account The account to start recovery for
    /// @param guardianSignatures Array of guardian signatures authorizing the recovery
    function startRecovery(
        address account,
        GuardianSignature[] calldata guardianSignatures
    ) external whenRecoveryIsNotStarted(account) {
        if (guardianSignatures.length < _recoveryConfigs[account].threshold) {
            revert ThresholdNotMet();
        }
        if (!guardianSignaturesAreValid(account, guardianSignatures)) {
            revert InvalidGuardianSignatures();
        }

        // increment nonce.
        _recoveryConfigs[account].nonce++;

        // set recovery start time.
        _recoveryConfigs[account].recoveryStart = block.timestamp;

        emit RecoveryStarted(account);
    }

    /// @notice Executes the recovery process after timelock period
    /// @dev Can only execute calls to reconfigure installed Validator Modules
    /// @param account The account to execute recovery for
    /// @param guardianSignatures Array of GuardianSignature authorizing the recovery
    /// @param executionCalldata The encoded call to reconfigure a Validator Module
    function executeRecovery(
        address account,
        GuardianSignature[] calldata guardianSignatures,
        bytes calldata executionCalldata
    ) external whenRecoveryIsReady(account) nonReentrant {
        if (guardianSignatures.length < _recoveryConfigs[account].threshold) {
            revert ThresholdNotMet();
        }
        if (!guardianSignaturesAreValid(account, guardianSignatures)) {
            revert InvalidGuardianSignatures();
        }

        // exection data should be at least:20 bytes for targetValidatorModule, 32 for value and 4 for recovery selector.
        if (executionCalldata.length < 56) {
            revert InvalidRecoveryCallData();
        }

        // @TBD sending value to the validator module.
        // Rationale: In some very specific scenarios, the validator module might need to be paid for the recovery,
        // or the recovery logic includes to take all the balance of the account.
        (address targetValidatorModule, , ) = ERC7579Utils.decodeSingle(executionCalldata);

        // check the target is an installed Validator Module on the account.
        if (!IERC7579ModuleConfig(account).isModuleInstalled(MODULE_TYPE_VALIDATOR, targetValidatorModule, "")) {
            revert InvalidInstalledValidatorModule();
        }

        // create single call mode
        Mode mode = ERC7579Utils.encodeMode(
            ERC7579Utils.CALLTYPE_SINGLE, // enforce single call
            ERC7579Utils.EXECTYPE_DEFAULT, // enforce revert on failure
            ModeSelector.wrap(0), // no selector needed
            ModePayload.wrap(bytes22(0)) // no payload needed
        );

        // increment nonce.
        _recoveryConfigs[account].nonce++;

        // reset recovery status.
        _recoveryConfigs[account].recoveryStart = 0;

        // execute the recovery.
        AccountERC7579(payable(account)).executeFromExecutor(Mode.unwrap(mode), executionCalldata);

        emit RecoveryExecuted(account, targetValidatorModule);
    }

    /// @notice Cancels an ongoing recovery process
    /// @dev Can only be called by the ERC-7579 Account itself
    function cancelRecovery() external whenRecoveryIsTimelockOrReady(msg.sender) {
        address account = msg.sender;

        _recoveryConfigs[account].recoveryStart = 0;

        emit RecoveryCancelled(account);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                SIGNATURE VERIFICATION
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Computes the EIP-712 digest (typed data hash) for a recovery request
    /// @dev Uses the current nonce to prevent replay attacks across recovery attempts
    /// @param account The account address for which the recovery digest is being generated
    /// @return bytes32 The EIP-712 compliant digest
    function _getRecoveryDigest(address account) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(RECOVERY_TYPEHASH, account, getNonce(account)));
        return _hashTypedDataV4(structHash);
    }

    /// @notice Verifies multiple guardian signatures
    /// @dev Checks each signature against the current recovery digest
    /// @param account The account the signatures are for
    /// @param guardianSignatures Array of guardian signatures to verify
    /// @return True if all signatures are valid, false otherwise
    function guardianSignaturesAreValid(
        address account,
        GuardianSignature[] calldata guardianSignatures
    ) public view returns (bool) {
        if (guardianSignatures.length > 32) {
            revert MaxGuardians();
        }

        for (uint256 i = 0; i < guardianSignatures.length; i++) {
            // check signature validity
            if (!guardianSignatureIsValid(account, guardianSignatures[i])) {
                return false;
            }
            // check for signature duplication @TBD optimize O(n^2)
            address currentSigner = guardianSignatures[i].signer;
            for (uint256 j = 0; j < i; j++) {
                if (guardianSignatures[j].signer == currentSigner) {
                    return false;
                }
            }
        }
        return true;
    }

    /// @notice Verifies a single guardian signature against the current recovery digest
    /// @dev Checks if the signature is valid and if the signer is a guardian
    /// @param account The account the signature is for
    /// @param guardianSignature The signature to verify
    /// @return true if the signature is valid, false otherwise
    function guardianSignatureIsValid(
        address account,
        GuardianSignature calldata guardianSignature
    ) public view returns (bool) {
        return
            isGuardian(account, guardianSignature.signer) &&
            SignatureChecker.isValidSignatureNow(
                guardianSignature.signer,
                _getRecoveryDigest(account),
                guardianSignature.signature
            );
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MODULE MANAGEMENT
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Adds a new guardian to the account's recovery configuration
    /// @dev Can only be called by the account itself
    /// @param guardian Address of the new guardian
    function addGuardian(address guardian) external {
        address account = msg.sender;

        if (_recoveryConfigs[account].guardians.length() >= MAX_GUARDIANS) {
            revert MaxGuardians();
        }

        if (guardian == address(0)) {
            revert InvalidGuardian();
        }

        bool added = _recoveryConfigs[account].guardians.add(guardian);
        if (!added) {
            revert AlreadyGuardian();
        }

        emit GuardianAdded(account, guardian);
    }

    /// @notice Removes a guardian from the account's recovery configuration
    /// @dev Can only be called by the account itself. Cannot remove if it would make threshold unreachable
    /// @param guardian Address of the guardian to remove
    function removeGuardian(address guardian) external {
        address account = msg.sender;

        if (_recoveryConfigs[account].guardians.length() == _recoveryConfigs[account].threshold) {
            revert CannotRemoveGuardian();
        }

        bool removed = _recoveryConfigs[account].guardians.remove(guardian);
        if (!removed) {
            revert GuardianNotFound();
        }

        emit GuardianRemoved(account, guardian);
    }

    /// @notice Changes the number of required guardian signatures
    /// @dev Can only be called by the ERC-7579 Account itself
    /// @param threshold New threshold value
    function changeThreshold(uint256 threshold) external {
        address account = msg.sender;

        if (threshold == 0 || threshold > _recoveryConfigs[account].guardians.length()) {
            revert InvalidThreshold();
        }

        _recoveryConfigs[account].threshold = threshold;

        emit ThresholdChanged(account, threshold);
    }

    /// @notice Changes the timelock duration for recovery
    /// @dev Can only be called by the account itself. Cannot be set to zero
    /// @param timelock New timelock duration in seconds
    function changeTimelock(uint256 timelock) external {
        address account = msg.sender;

        if (timelock == 0) {
            revert InvalidTimelock();
        }

        _recoveryConfigs[account].timelock = timelock;

        emit TimelockChanged(account, timelock);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Gets the current recovery status for an account
    /// @param account The account to query
    /// @return RecoveryStatus enum value (NotStarted, Timelock, or Ready)
    function getRecoveryStatus(address account) public view returns (RecoveryStatus) {
        RecoveryConfig storage recoveryConfig = _recoveryConfigs[account];

        if (recoveryConfig.recoveryStart == 0) {
            return RecoveryStatus.NotStarted;
        }

        if (block.timestamp < recoveryConfig.recoveryStart + recoveryConfig.timelock) {
            return RecoveryStatus.Timelock;
        }

        return RecoveryStatus.Ready;
    }

    function getNonce(address account) public view returns (uint256) {
        return _recoveryConfigs[account].nonce;
    }

    function getGuardians(address account) public view returns (address[] memory) {
        return _recoveryConfigs[account].guardians.values();
    }

    function getThreshold(address account) public view returns (uint256) {
        return _recoveryConfigs[account].threshold;
    }

    function getTimelock(address account) public view returns (uint256) {
        return _recoveryConfigs[account].timelock;
    }

    function isGuardian(address account, address guardian) public view returns (bool) {
        return _recoveryConfigs[account].guardians.contains(guardian);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MODULE METADATA
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the name of the module
    /// @return The name of the module
    function name() external pure returns (string memory) {
        return NAME;
    }

    /// @notice Returns the version of the module
    /// @return The version of the module
    function version() external pure returns (string memory) {
        return VERSION;
    }

    /// @notice Checks if the module is of a certain type
    /// @param moduleTypeId The module type ID to check
    /// @return true if the module is of the given type, false otherwise
    function isModuleType(uint256 moduleTypeId) external pure override returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR;
    }
}
