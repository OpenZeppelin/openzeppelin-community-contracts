// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7579Module, IERC7579ModuleConfig, MODULE_TYPE_EXECUTOR, MODULE_TYPE_VALIDATOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {ERC7579Utils, Mode, CallType, ModeSelector, ExecType, ModePayload} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {AccountERC7579} from "../AccountERC7579.sol";

/**
 * @title Social Recovery Executor Module
 *
 * @dev Implementation of a social recovery mechanism for ERC-7579 Accounts that enables
 * account recovery through a guardian-based consensus mechanism. Provides M-of-N guardian
 * approval with timelock protection, recovery cancellation, and configurable security parameters.
 *
 * The module allows accounts to:
 * - Recover access through guardian approval
 * - Configure guardian designations and thresholds
 * - Protect against unauthorized recovery attempts
 */
contract SocialRecoveryExecutor is IERC7579Module, EIP712, Nonces {
    using EnumerableSet for EnumerableSet.AddressSet;

    enum RecoveryStatus {
        NotStarted,
        Started,
        Ready
    }

    struct RecoveryConfig {
        EnumerableSet.AddressSet guardians;
        bytes32 pendingExecutionHash;
        uint256 recoveryStart;
        uint256 threshold;
        uint256 timelock;
    }

    struct GuardianSignature {
        bytes signature;
        address signer;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                CONSTANTS & STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    bytes32 private constant START_RECOVERY_TYPEHASH =
        keccak256("StartRecovery(address account,bytes executionCalldata,uint256 nonce)");

    bytes32 private constant CANCEL_RECOVERY_TYPEHASH = keccak256("CancelRecovery(address account,uint256 nonce)");

    mapping(address account => RecoveryConfig recoveryConfig) private _recoveryConfigs;

    /*//////////////////////////////////////////////////////////////////////////
                                EVENTS & ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    event ModuleUninstalledReceived(address indexed account, bytes data);
    event ModuleInstalledReceived(address indexed account, bytes data);

    event RecoveryCancelled(address indexed account);
    event RecoveryExecuted(address indexed account);
    event RecoveryStarted(address indexed account);

    event ThresholdChanged(address indexed account, uint256 indexed threshold);
    event TimelockChanged(address indexed account, uint256 indexed timelock);
    event GuardianRemoved(address indexed account, address indexed guardian);
    event GuardianAdded(address indexed account, address indexed guardian);

    error InvalidThreshold();
    error InvalidGuardians();
    error InvalidGuardian();
    error InvalidTimelock();

    error CannotRemoveGuardian();
    error GuardianNotFound();
    error TooManyGuardians();
    error AlreadyGuardian();

    error ExecutionDiffersFromPending();
    error DuplicateGuardianSignature();
    error TooManyGuardianSignatures();
    error InvalidGuardianSignature();
    error ThresholdNotMet();

    error RecoveryAlreadyStarted();
    error RecoveryNotStarted();
    error RecoveryNotReady();

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

    modifier whenRecoveryIsStartedOrReady(address account) {
        if (getRecoveryStatus(account) == RecoveryStatus.NotStarted) {
            revert RecoveryNotStarted();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MODULE SETUP CONFIGURATION
    //////////////////////////////////////////////////////////////////////////*/

    constructor(string memory name, string memory version) EIP712(name, version) {}

    /// @notice Initializes the module with initial recovery configuration
    /// @dev Called by the ERC-7579 Account during module installation
    /// @param data initData ABI encoded (address[] guardians, uint256 threshold, uint256 timelock)
    function onInstall(bytes calldata data) external virtual override {
        address account = msg.sender;

        (address[] memory _guardians, uint256 _threshold, uint256 _timelock) = abi.decode(
            data,
            (address[], uint256, uint256)
        );
        if (_guardians.length == 0) {
            revert InvalidGuardians();
        }
        if (_threshold == 0 || _threshold > _guardians.length) {
            revert InvalidThreshold();
        }
        if (_timelock == 0) {
            revert InvalidTimelock();
        }

        for (uint256 i = 0; i < _guardians.length; i++) {
            _addGuardian(account, _guardians[i]);
        }

        _recoveryConfigs[account].threshold = _threshold;
        _recoveryConfigs[account].timelock = _timelock;

        emit ModuleInstalledReceived(account, data);
    }

    /// @notice Uninstalls the module, clearing all recovery configuration
    /// @dev Called by the ERC-7579 Account during module uninstallation
    /// @param data Additional data
    function onUninstall(bytes calldata data) external virtual override {
        address account = msg.sender;

        // clear the guardian EnumerableSet.
        _recoveryConfigs[account].guardians.clear();

        // slither-disable-next-line mapping-deletion
        delete _recoveryConfigs[account];

        emit ModuleUninstalledReceived(account, data);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MODULE MAIN LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Starts the recovery process for an ERC-7579 Account
    /// @dev Requires threshold number of valid guardian signatures and commits execution hash
    /// @param account The ERC-7579 Account to start recovery for
    /// @param guardianSignatures Array of guardian signatures authorizing the recovery
    /// @param executionCalldata The calldata to execute during recovery
    /// @custom:security Uses EIP-712 for signature verification and nonces for replay protection
    function startRecovery(
        address account,
        GuardianSignature[] calldata guardianSignatures,
        bytes calldata executionCalldata
    ) external virtual whenRecoveryIsNotStarted(account) {
        bytes32 digest = _getStartRecoveryDigest(account, executionCalldata);
        _validateGuardianSignatures(account, guardianSignatures, digest);
        _useNonce(account);

        // store and start the recovery process.
        _recoveryConfigs[account].pendingExecutionHash = keccak256(executionCalldata);
        _recoveryConfigs[account].recoveryStart = block.timestamp;

        emit RecoveryStarted(account);
    }

    /// @notice Executes the recovery process after timelock period
    /// @dev Only callable when recovery status is Ready
    /// @param account The account to execute recovery for
    /// @param executionCalldata The calldata to execute, must match the pending recovery digest
    /// @custom:security Validates execution matches the hash committed during startRecovery
    function executeRecovery(
        address account,
        bytes calldata executionCalldata
    ) external virtual whenRecoveryIsReady(account) {
        if (keccak256(executionCalldata) != _recoveryConfigs[account].pendingExecutionHash) {
            revert ExecutionDiffersFromPending();
        }

        // reset recovery status.
        _recoveryConfigs[account].pendingExecutionHash = bytes32(0);
        _recoveryConfigs[account].recoveryStart = 0;

        // execute the recovery.
        // slither-disable-next-line reentrancy-no-eth
        Address.functionCall(account, executionCalldata);

        emit RecoveryExecuted(account);
    }

    /// @notice Cancels an ongoing recovery process
    /// @dev Can only be called by the account itself
    /// @custom:security Direct account control takes precedence over recovery process
    function cancelRecovery() external virtual whenRecoveryIsStartedOrReady(msg.sender) {
        _cancelRecovery(msg.sender);
    }

    /// @notice Overload: Allows guardians to cancel a recovery process
    /// @dev Requires threshold signatures, similar to starting recovery
    /// @param account The account to cancel recovery for
    /// @param guardianSignatures Array of guardian signatures authorizing cancellation
    /// @custom:security Uses same signature threshold as recovery initiation
    function cancelRecovery(
        address account,
        GuardianSignature[] calldata guardianSignatures
    ) external virtual whenRecoveryIsStartedOrReady(account) {
        bytes32 digest = _getCancelRecoveryDigest(account, nonces(account));
        _validateGuardianSignatures(account, guardianSignatures, digest);
        _useNonce(account);

        _cancelRecovery(account);
    }

    /// @notice Validates guardian signatures for a given digest
    /// @dev Helper function for clients to validate signatures
    /// @param account The ERC-7579 Account to validate signatures for
    /// @param guardianSignatures Array of guardian signatures to validate
    /// @param digest The digest to validate the signatures against
    function validateGuardianSignatures(
        address account,
        GuardianSignature[] calldata guardianSignatures,
        bytes32 digest
    ) external view {
        _validateGuardianSignatures(account, guardianSignatures, digest);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MODULE MANAGEMENT
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Adds a new guardian to the account's recovery configuration
    /// @dev Only callable by the account itself
    /// @param guardian Address of the new guardian
    function addGuardian(address guardian) external {
        _addGuardian(msg.sender, guardian);
    }

    /// @notice Removes a guardian from the account's recovery configuration
    /// @dev Only callable by the account itself
    /// @param guardian Address of the guardian to remove
    function removeGuardian(address guardian) external {
        _removeGuardian(msg.sender, guardian);
    }

    /// @notice Changes the number of required guardian signatures
    /// @dev Only callable by the account itself
    /// @param threshold New threshold value
    function changeThreshold(uint256 threshold) external {
        _changeThreshold(msg.sender, threshold);
    }

    /// @notice Changes the timelock duration for recovery
    /// @dev Only callable by the account itself
    /// @param timelock New timelock duration in seconds
    function changeTimelock(uint256 timelock) external {
        _changeTimelock(msg.sender, timelock);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Gets the current recovery status of an ERC-7579 Account
    /// @param account The ERC-7579 Account to get the recovery status for
    /// @return The current recovery status
    function getRecoveryStatus(address account) public view virtual returns (RecoveryStatus) {
        uint256 recoveryStart = _recoveryConfigs[account].recoveryStart;
        if (recoveryStart == 0) {
            return RecoveryStatus.NotStarted;
        }
        if (block.timestamp < recoveryStart + _recoveryConfigs[account].timelock) {
            return RecoveryStatus.Started;
        }
        return RecoveryStatus.Ready;
    }

    function isGuardian(address account, address guardian) public view returns (bool) {
        return _recoveryConfigs[account].guardians.contains(guardian);
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

    function maxGuardians() public pure virtual returns (uint256) {
        return 32;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Verifies multiple guardian signatures for a given digest
    /// @dev Ensures each signer is an unique guardian, and threshold is met
    /// @param account The account the signatures are for
    /// @param guardianSignatures Array of guardian signatures to verify
    /// @param digest The digest to verify the signatures against
    function _validateGuardianSignatures(
        address account,
        GuardianSignature[] calldata guardianSignatures,
        bytes32 digest
    ) internal view virtual {
        // bound `for` cycle
        if (guardianSignatures.length > maxGuardians()) {
            revert TooManyGuardianSignatures();
        }
        if (guardianSignatures.length < _recoveryConfigs[account].threshold) {
            revert ThresholdNotMet();
        }

        for (uint256 i = 0; i < guardianSignatures.length; i++) {
            if (
                !isGuardian(account, guardianSignatures[i].signer) ||
                !SignatureChecker.isValidSignatureNow(
                    guardianSignatures[i].signer,
                    digest,
                    guardianSignatures[i].signature
                )
            ) {
                revert InvalidGuardianSignature();
            }
            // @TBD optimize O(n^2): check for signature duplication
            address currentSigner = guardianSignatures[i].signer;
            for (uint256 j = 0; j < i; j++) {
                if (guardianSignatures[j].signer == currentSigner) {
                    revert DuplicateGuardianSignature();
                }
            }
        }
    }

    /// @notice EIP-712 digest for starting recovery
    /// @param account The ERC-7579 Account to start recovery for
    /// @param executionCalldata The calldata to execute during recovery
    /// @return The EIP-712 digest for starting recovery
    function _getStartRecoveryDigest(address account, bytes memory executionCalldata) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(START_RECOVERY_TYPEHASH, account, keccak256(executionCalldata), nonces(account))
        );
        return _hashTypedDataV4(structHash);
    }

    /// @notice EIP-712 digest for cancelling recovery
    /// @param account The ERC-7579 Account to cancel recovery for
    /// @param nonce The nonce of the account
    /// @return The EIP-712 digest for cancelling recovery
    function _getCancelRecoveryDigest(address account, uint256 nonce) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(CANCEL_RECOVERY_TYPEHASH, account, nonce));
        return _hashTypedDataV4(structHash);
    }

    /// @notice Cancels an ongoing recovery process
    /// @param account The ERC-7579 Account to cancel recovery for
    function _cancelRecovery(address account) internal virtual {
        _recoveryConfigs[account].pendingExecutionHash = bytes32(0);
        _recoveryConfigs[account].recoveryStart = 0;
        emit RecoveryCancelled(account);
    }

    /// @notice Adds a new guardian to the account's recovery configuration
    /// @param account The ERC-7579 Account to add the guardian to
    /// @param guardian Address of the new guardian
    function _addGuardian(address account, address guardian) internal virtual {
        if (guardian == address(0)) {
            revert InvalidGuardian();
        }
        if (_recoveryConfigs[account].guardians.length() >= maxGuardians()) {
            revert TooManyGuardians();
        }
        if (!_recoveryConfigs[account].guardians.add(guardian)) {
            revert AlreadyGuardian();
        }
        emit GuardianAdded(account, guardian);
    }

    /// @notice Removes a guardian from the account's recovery configuration
    /// @dev Cannot remove if it would make threshold unreachable
    /// @param account The ERC-7579 Account to remove the guardian from
    /// @param guardian Address of the guardian to remove
    function _removeGuardian(address account, address guardian) internal virtual {
        if (_recoveryConfigs[account].guardians.length() == _recoveryConfigs[account].threshold) {
            revert CannotRemoveGuardian();
        }
        if (!_recoveryConfigs[account].guardians.remove(guardian)) {
            revert GuardianNotFound();
        }
        emit GuardianRemoved(account, guardian);
    }

    /// @notice Changes the number of required guardian signatures
    /// @dev Cannot be set to zero and cannot be greater than the current number of guardians
    /// @param account The ERC-7579 Account to change the threshold for
    /// @param threshold New threshold value
    function _changeThreshold(address account, uint256 threshold) internal virtual {
        if (threshold == 0 || threshold > _recoveryConfigs[account].guardians.length()) {
            revert InvalidThreshold();
        }
        _recoveryConfigs[account].threshold = threshold;
        emit ThresholdChanged(account, threshold);
    }

    /// @notice Changes the timelock duration for recovery
    /// @dev Cannot be set to zero
    /// @param account The ERC-7579 Account to change the timelock for
    /// @param timelock New timelock duration in seconds
    function _changeTimelock(address account, uint256 timelock) internal virtual {
        if (timelock == 0) {
            revert InvalidTimelock();
        }
        _recoveryConfigs[account].timelock = timelock;
        emit TimelockChanged(account, timelock);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MODULE METADATA
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks if the module is of a certain type
    /// @param moduleTypeId The module type ID to check
    /// @return true if the module is of the given type, false otherwise
    function isModuleType(uint256 moduleTypeId) external pure override returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR;
    }
}
