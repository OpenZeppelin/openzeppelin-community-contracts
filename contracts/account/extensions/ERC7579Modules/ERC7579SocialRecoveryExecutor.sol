// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7579Module, MODULE_TYPE_EXECUTOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";

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
contract ERC7579SocialRecoveryExecutor is IERC7579Module, EIP712, Nonces {
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

    event ThresholdChanged(address indexed account, uint256 threshold);
    event TimelockChanged(address indexed account, uint256 timelock);
    event GuardianRemoved(address indexed account, address guardian);
    event GuardianAdded(address indexed account, address guardian);

    error InvalidThreshold();
    error InvalidGuardians();
    error InvalidGuardian();
    error InvalidTimelock();

    error CannotRemoveGuardian();
    error GuardianNotFound();
    error TooManyGuardians();
    error AlreadyGuardian();

    error DuplicatedOrUnsortedGuardianSignatures();
    error ExecutionDiffersFromPending();
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

    /// @inheritdoc IERC7579Module
    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == MODULE_TYPE_EXECUTOR;
    }

    /// @inheritdoc IERC7579Module
    function onInstall(bytes memory data) public virtual override {
        address account = msg.sender;

        (address[] memory _guardians, uint256 _threshold, uint256 _timelock) = abi.decode(
            data,
            (address[], uint256, uint256)
        );

        if (_guardians.length == 0) {
            revert InvalidGuardians();
        }

        for (uint256 i = 0; i < _guardians.length; i++) {
            _addGuardian(account, _guardians[i]);
        }

        _setThreshold(account, _threshold);
        _setTimelock(account, _timelock);

        emit ModuleInstalledReceived(account, data);
    }

    /// @inheritdoc IERC7579Module
    function onUninstall(bytes calldata data) public virtual override {
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
    ) public virtual whenRecoveryIsNotStarted(account) {
        bytes32 digest = _getStartRecoveryDigest(account, executionCalldata, _useNonce(account));
        _validateGuardianSignatures(account, guardianSignatures, digest);

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
    ) public virtual whenRecoveryIsReady(account) {
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
    function cancelRecovery() public virtual whenRecoveryIsStartedOrReady(msg.sender) {
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
    ) public virtual whenRecoveryIsStartedOrReady(account) {
        bytes32 digest = _getCancelRecoveryDigest(account, _useNonce(account));
        _validateGuardianSignatures(account, guardianSignatures, digest);

        _cancelRecovery(account);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MODULE MANAGEMENT
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Adds a new guardian to the account's recovery configuration
    /// @dev Only callable by the account itself
    /// @param guardian Address of the new guardian
    function addGuardian(address guardian) public virtual {
        _addGuardian(msg.sender, guardian);
    }

    /// @notice Removes a guardian from the account's recovery configuration
    /// @dev Only callable by the account itself
    /// @param guardian Address of the guardian to remove
    function removeGuardian(address guardian) public virtual {
        _removeGuardian(msg.sender, guardian);
    }

    /// @notice Changes the number of required guardian signatures
    /// @dev Only callable by the account itself
    /// @param threshold New threshold value
    function updateThreshold(uint256 threshold) public virtual {
        _setThreshold(msg.sender, threshold);
    }

    /// @notice Changes the timelock duration for recovery
    /// @dev Only callable by the account itself
    /// @param timelock New timelock duration in seconds
    function updateTimelock(uint256 timelock) public virtual {
        _setTimelock(msg.sender, timelock);
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

    /// @notice Checks if an address is a guardian for an ERC-7579 Account
    /// @param account The ERC-7579 Account to check guardians for
    /// @param guardian The address to check as a guardian
    /// @return true if the address is a guardian, false otherwise
    function isGuardian(address account, address guardian) public view virtual returns (bool) {
        return _recoveryConfigs[account].guardians.contains(guardian);
    }

    /// @notice Gets all guardians for an ERC-7579 Account
    /// @param account The ERC-7579 Account to get guardians for
    /// @return An array of all guardians
    function getGuardians(address account) public view virtual returns (address[] memory) {
        return _recoveryConfigs[account].guardians.values();
    }

    /// @notice Gets the threshold for an ERC-7579 Account
    /// @param account The ERC-7579 Account to get the threshold for
    /// @return The threshold value
    function getThreshold(address account) public view virtual returns (uint256) {
        return _recoveryConfigs[account].threshold;
    }

    /// @notice Gets the timelock for an ERC-7579 Account
    /// @param account The ERC-7579 Account to get the timelock for
    /// @return The timelock value
    function getTimelock(address account) public view virtual returns (uint256) {
        return _recoveryConfigs[account].timelock;
    }

    /// @notice Gets the maximum number of guardians for an ERC-7579 Account
    /// @return The maximum number of guardians
    function maxGuardians() public pure virtual returns (uint256) {
        return 32;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice EIP-712 digest for starting recovery
    /// @param account The ERC-7579 Account to start recovery for
    /// @param executionCalldata The calldata to execute during recovery
    /// @return The EIP-712 digest for starting recovery
    function _getStartRecoveryDigest(
        address account,
        bytes calldata executionCalldata,
        uint256 nonce
    ) internal view virtual returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(START_RECOVERY_TYPEHASH, account, keccak256(executionCalldata), nonce)
        );
        return _hashTypedDataV4(structHash);
    }

    /// @notice EIP-712 digest for cancelling recovery
    /// @param account The ERC-7579 Account to cancel recovery for
    /// @param nonce The nonce of the account
    /// @return The EIP-712 digest for cancelling recovery
    function _getCancelRecoveryDigest(address account, uint256 nonce) internal view virtual returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(CANCEL_RECOVERY_TYPEHASH, account, nonce));
        return _hashTypedDataV4(structHash);
    }

    /// @notice Verifies multiple guardian signatures for a given digest
    /// @dev Ensures signatures are unique, and threshold is met
    /// @param account The account the signatures are for
    /// @param guardianSignatures Array of guardian signatures sorted by signer address in ascending order
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

        address lastSigner = address(0);
        for (uint256 i = 0; i < guardianSignatures.length; i++) {
            address signer = guardianSignatures[i].signer;
            if (
                !isGuardian(account, signer) ||
                !SignatureChecker.isValidSignatureNow(signer, digest, guardianSignatures[i].signature)
            ) {
                revert InvalidGuardianSignature();
            }
            if (uint160(signer) <= uint160(lastSigner)) {
                revert DuplicatedOrUnsortedGuardianSignatures();
            }
            lastSigner = signer;
        }
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
    function _setThreshold(address account, uint256 threshold) internal virtual {
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
    function _setTimelock(address account, uint256 timelock) internal virtual {
        if (timelock == 0) {
            revert InvalidTimelock();
        }
        _recoveryConfigs[account].timelock = timelock;
        emit TimelockChanged(account, timelock);
    }
}
