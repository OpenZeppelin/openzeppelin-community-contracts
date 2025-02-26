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
 * @dev Social recovery module enabling account reconfiguration through a timelocked
 * guardian-based consensus mechanism. Provides M-of-N guardian multi-signature with
 * timelock protection, recovery cancellation, and configurable security parameters.
 */
contract ERC7579SocialRecoveryExecutor is IERC7579Module, EIP712, Nonces {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Status of the recovery process used to determine what actions are currently allowed
    /// @param NotStarted No recovery process has started
    /// @param Started Recovery process has started but timelock hasn't expired
    /// @param Ready Recovery process has passed timelock and is ready for execution
    enum RecoveryStatus {
        NotStarted,
        Started,
        Ready
    }

    /// @dev Recovery configuration for an ERC-7579 Account containing all necessary information for the recovery process
    struct RecoveryConfig {
        EnumerableSet.AddressSet guardians;
        bytes32 pendingExecutionHash;
        uint256 recoveryStart;
        uint256 threshold;
        uint256 timelock;
    }

    /// @dev Structure representing a guardian's signature used for verification in recovery operations
    /// @param signature The cryptographic signature bytes
    /// @param signer The address of the guardian who signed
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

    error DuplicatedOrUnsortedGuardianSignatures();
    error ExecutionDiffersFromPending();
    error TooManyGuardianSignatures();
    error InvalidGuardianSignature();
    error ThresholdNotMet();

    error RecoveryAlreadyStarted();
    error RecoveryNotStarted();
    error RecoveryNotReady();

    error InvalidGuardianLength();
    error InvalidThreshold();
    error InvalidTimelock();

    error CannotRemoveGuardian();
    error GuardianNotFound();
    error TooManyGuardians();
    error AlreadyGuardian();

    /*///////////////////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Reverts if the recovery process has already started.
    modifier whenRecoveryIsNotStarted(address account) {
        if (getRecoveryStatus(account) != RecoveryStatus.NotStarted) {
            revert RecoveryAlreadyStarted();
        }
        _;
    }

    /// @dev Reverts if the recovery process is not ready to be executed.
    modifier whenRecoveryIsReady(address account) {
        if (getRecoveryStatus(account) != RecoveryStatus.Ready) {
            revert RecoveryNotReady();
        }
        _;
    }

    /// @dev Reverts if the recovery process is not started or ready.
    modifier whenRecoveryIsStartedOrReady(address account) {
        if (getRecoveryStatus(account) == RecoveryStatus.NotStarted) {
            revert RecoveryNotStarted();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                MODULE SETUP CONFIGURATION
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Initializes the module with a name and version.
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
            revert InvalidGuardianLength();
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

    /// @dev Starts the recovery process for an ERC-7579 Account. Requires threshold number of valid guardian signatures and commits the hash of the approved execution calldata for recovery.
    /// @param account The ERC-7579 Account to start recovery for
    /// @param guardianSignatures Array of guardian signatures authorizing the recovery. Each signature contains a signature and the signer's address, sorted by signer address in ascending order.
    /// @param executionCalldata The calldata to execute during recovery. This defines the account reconfiguration to perform.
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

    /// @dev Executes the recovery process after timelock period has passed. Only callable when recovery status is Ready. Validates that execution matches the hash committed during startRecovery and resets recovery state afterward.
    /// @param account The account to execute recovery for
    /// @param executionCalldata The calldata to execute, must match the pending recovery hash stored during startRecovery
    /// @custom:security Validates execution matches the hash committed during startRecovery and resets recovery state afterward
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

    /// @dev Cancels an ongoing recovery process. Can only be called by the account itself for self-cancellation.
    /// @custom:security Direct account control takes precedence over recovery process
    function cancelRecovery() public virtual whenRecoveryIsStartedOrReady(msg.sender) {
        _cancelRecovery(msg.sender);
    }

    /// @dev Allows guardians to cancel a recovery process. Requires threshold signatures from guardians, similar to starting recovery.
    /// Uses same signature threshold and verification process as recovery initiation.
    /// @param account The account to cancel recovery for
    /// @param guardianSignatures Array of guardian signatures authorizing cancellation, sorted by signer address
    /// @custom:security Uses same signature threshold and verification process as recovery initiation
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

    /// @dev Adds a new guardian to the account's recovery configuration. Only callable by the account itself.
    /// @param guardian Address of the new guardian
    function addGuardian(address guardian) public virtual {
        _addGuardian(msg.sender, guardian);
    }

    /// @dev Removes a guardian from the account's recovery configuration. Only callable by the account itself.
    /// @param guardian Address of the guardian to remove
    function removeGuardian(address guardian) public virtual {
        _removeGuardian(msg.sender, guardian);
    }

    /// @dev Changes the number of required guardian signatures. Only callable by the account itself.
    /// @param threshold New threshold value
    function updateThreshold(uint256 threshold) public virtual {
        _setThreshold(msg.sender, threshold);
    }

    /// @dev Changes the timelock duration for recovery. Only callable by the account itself.
    /// @param timelock New timelock duration in seconds
    function updateTimelock(uint256 timelock) public virtual {
        _setTimelock(msg.sender, timelock);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Gets the current recovery status of an ERC-7579 Account. Determines status based on recoveryStart timestamp and timelock duration.
    /// @param account The ERC-7579 Account to get the recovery status for
    /// @return Status enum value: NotStarted (0), Started (1), or Ready (2)
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

    /// @dev Checks if an address is a guardian for an ERC-7579 Account.
    /// @param account The ERC-7579 Account to check guardians for
    /// @param guardian The address to check as a guardian
    /// @return true if the address is a guardian, false otherwise
    function isGuardian(address account, address guardian) public view virtual returns (bool) {
        return _recoveryConfigs[account].guardians.contains(guardian);
    }

    /// @dev Gets all guardians for an ERC-7579 Account.
    /// @param account The ERC-7579 Account to get guardians for
    /// @return An array of all guardians
    function getGuardians(address account) public view virtual returns (address[] memory) {
        return _recoveryConfigs[account].guardians.values();
    }

    /// @dev Gets the threshold for an ERC-7579 Account.
    /// @param account The ERC-7579 Account to get the threshold for
    /// @return The threshold value
    function getThreshold(address account) public view virtual returns (uint256) {
        return _recoveryConfigs[account].threshold;
    }

    /// @dev Gets the timelock for an ERC-7579 Account.
    /// @param account The ERC-7579 Account to get the timelock for
    /// @return The timelock value
    function getTimelock(address account) public view virtual returns (uint256) {
        return _recoveryConfigs[account].timelock;
    }

    /// @dev Gets the maximum number of guardians for an ERC-7579 Account.
    /// @return The maximum number of guardians
    function getMaxGuardians() public pure virtual returns (uint256) {
        return 32;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev EIP-712 digest for starting recovery.
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

    /// @dev EIP-712 digest for cancelling recovery.
    /// @param account The ERC-7579 Account to cancel recovery for
    /// @param nonce The nonce of the account
    /// @return The EIP-712 digest for cancelling recovery
    function _getCancelRecoveryDigest(address account, uint256 nonce) internal view virtual returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(CANCEL_RECOVERY_TYPEHASH, account, nonce));
        return _hashTypedDataV4(structHash);
    }

    /// @dev Verifies multiple guardian signatures for a given digest. Ensures signatures are unique, properly sorted, and threshold is met.
    /// @param account The account the signatures are for
    /// @param guardianSignatures Array of guardian signatures sorted by signer address in ascending order
    /// @param digest The EIP-712 typed data digest to verify the signatures against
    /// @custom:security Enforces ascending order of signers to prevent duplicates
    function _validateGuardianSignatures(
        address account,
        GuardianSignature[] calldata guardianSignatures,
        bytes32 digest
    ) internal view virtual {
        // bound `for` cycle
        if (guardianSignatures.length > getMaxGuardians()) {
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

    /// @dev Cancels an ongoing recovery process.
    /// @param account The ERC-7579 Account to cancel recovery for
    function _cancelRecovery(address account) internal virtual {
        _recoveryConfigs[account].pendingExecutionHash = bytes32(0);
        _recoveryConfigs[account].recoveryStart = 0;
        emit RecoveryCancelled(account);
    }

    /// @dev Adds a new guardian to the account's recovery configuration.
    /// @param account The ERC-7579 Account to add the guardian to
    /// @param guardian Address of the new guardian
    function _addGuardian(address account, address guardian) internal virtual {
        if (_recoveryConfigs[account].guardians.length() >= getMaxGuardians()) {
            revert TooManyGuardians();
        }
        if (!_recoveryConfigs[account].guardians.add(guardian)) {
            revert AlreadyGuardian();
        }
        emit GuardianAdded(account, guardian);
    }

    /// @dev Removes a guardian from the account's recovery configuration. Cannot remove if it would make threshold unreachable.
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

    /// @dev Changes the number of required guardian signatures. Cannot be set to zero and cannot be greater than the current number of guardians.
    /// @param account The ERC-7579 Account to change the threshold for
    /// @param threshold New threshold value
    function _setThreshold(address account, uint256 threshold) internal virtual {
        if (threshold == 0 || threshold > _recoveryConfigs[account].guardians.length()) {
            revert InvalidThreshold();
        }
        _recoveryConfigs[account].threshold = threshold;
        emit ThresholdChanged(account, threshold);
    }

    /// @dev Changes the timelock duration for recovery. Cannot be set to zero.
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
