// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC7579BaseExecutor} from "./ERC7579BaseExecutor.sol";
import {ERC7913Utils} from "../../utils/cryptography/ERC7913Utils.sol";
import {EnumerableSetExtended} from "../../utils/structs/EnumerableSetExtended.sol";
import {Mode} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";

/**
 * @dev Implementation of {ERC7579BaseExecutor} that uses ERC-7913 signers for multisignature
 * operation scheduling.
 *
 * This module extends the base time-delayed executor with multisignature capabilities,
 * allowing an operation to be scheduled once it has been signed by a required threshold
 * of authorized signers. The signers are represented using the ERC-7913 format,
 * which concatenates a verifier address and a key: `verifier || key`.
 *
 * Operations can be scheduled using either:
 * - The account itself through the standard {schedule} function
 * - Or by collecting signatures from multiple authorized signers through {scheduleMultisigner}
 *
 * Example use case:
 *
 * A smart account with this module installed can schedule social recovery operations
 * after obtaining approval from a set number of signers (e.g., 3-of-5 guardians),
 * and then execute them after the time delay has passed.
 */
contract ERC7579MultisigExecutor is ERC7579BaseExecutor {
    using EnumerableSetExtended for EnumerableSetExtended.BytesSet;
    using ERC7913Utils for bytes32;
    using ERC7913Utils for bytes;

    /// @dev Emitted when signers are added.
    event ERC7913SignersAdded(address indexed account, bytes[] signers);

    /// @dev Emitted when signers are removed.
    event ERC7913SignersRemoved(address indexed account, bytes[] signers);

    /// @dev Emitted when the threshold is updated.
    event ERC7913ThresholdSet(address indexed account, uint256 threshold);

    /// @dev The `signer` already exists.
    error ERC7579MultisigExecutorAlreadyExists(bytes signer);

    /// @dev The `signer` does not exist.
    error ERC7579MultisigExecutorNonexistentSigner(bytes signer);

    /// @dev The `signer` is less than 20 bytes long.
    error ERC7579MultisigExecutorInvalidSigner(bytes signer);

    /// @dev The `threshold` is unreachable given the number of `signers`.
    error ERC7579MultisigExecutorUnreachableThreshold(uint256 signers, uint256 threshold);

    /// @dev The signatures are invalid.
    error ERC7579MultisigExecutorInvalidSignatures();

    mapping(address account => EnumerableSetExtended.BytesSet) private _signersSetByAccount;
    mapping(address account => uint256) private _thresholdByAccount;

    /**
     * @dev Sets up the module's initial configuration when installed by an account.
     * See {ERC7579BaseExecutor-onInstall}. Besides the delay setup, the `initdata` can
     * include `signers` and `threshold`.
     *
     * The initData should be encoded as:
     * `abi.encode(uint32 initialDelay, bytes[] signers, uint256 threshold)`
     *
     * If no signers or threshold are provided, the multisignature functionality will be
     * disabled until they are added later.
     */
    function onInstall(bytes calldata initData) public virtual override {
        super.onInstall(initData);

        if (initData.length > 32) {
            // More than just delay parameter
            (, bytes[] memory signers_, uint256 threshold_) = abi.decode(initData, (uint32, bytes[], uint256));
            _addSigners(msg.sender, signers_);
            _setThreshold(msg.sender, threshold_);
        }
    }

    /**
     * @dev Cleans up module's configuration when uninstalled from an account.
     * Clears all signers and resets the threshold.
     *
     * See {ERC7579BaseExecutor-onUninstall}.
     *
     * WARNING: This function has unbounded gas costs and may become uncallable if the set grows too large.
     * See {EnumerableSetExtended-clear}.
     */
    function onUninstall(bytes calldata data) public virtual override {
        _signersSetByAccount[msg.sender].clear();
        delete _thresholdByAccount[msg.sender];
        super.onUninstall(data);
    }

    /// @dev Returns the unique identifier of the `signer`.
    function signerId(bytes memory signer) public pure virtual returns (bytes32) {
        return keccak256(signer);
    }

    /**
     * @dev Returns the set of authorized signers for the specified account.
     *
     * WARNING: This operation copies the entire signers set to memory, which
     * can be expensive or may result in unbounded computation.
     */
    function signers(address account) public view virtual returns (bytes[] memory) {
        return _signersSetByAccount[account].values();
    }

    /// @dev Returns whether the `signer` is an authorized signer for the specified account.
    function isSigner(address account, bytes memory signer) public view virtual returns (bool) {
        return _signersSetByAccount[account].contains(signer);
    }

    /// @dev Returns the set of authorized signers for the specified account.
    function _signers(address account) internal view virtual returns (EnumerableSetExtended.BytesSet storage) {
        return _signersSetByAccount[account];
    }

    /**
     * @dev Returns the minimum number of signers required to approve a multisignature operation
     * for the specified account.
     */
    function threshold(address account) public view virtual returns (uint256) {
        return _thresholdByAccount[account];
    }

    /**
     * @dev Adds new signers to the authorized set for the calling account.
     * Can only be called by the account itself.
     */
    function addSigners(bytes[] memory newSigners) public virtual {
        _addSigners(msg.sender, newSigners);
    }

    /**
     * @dev Removes signers from the authorized set for the calling account.
     * Can only be called by the account itself.
     */
    function removeSigners(bytes[] memory oldSigners) public virtual {
        _removeSigners(msg.sender, oldSigners);
    }

    /**
     * @dev Sets the threshold for the calling account.
     * Can only be called by the account itself.
     */
    function setThreshold(uint256 newThreshold) public virtual {
        _setThreshold(msg.sender, newThreshold);
    }

    /**
     * @dev Schedules an operation using signatures from multiple authorized {signers}.
     * The operation will be scheduled if the number of valid signatures meets or exceeds
     * the threshold set for the target account.
     *
     * The signature should be encoded as:
     * `abi.encode(bytes[] signingSigners, bytes[] signatures)`
     *
     * Where signingSigners are the authorized signers and signatures are their corresponding
     * signatures of the operation hash. See {hashOperation} for the operation hash.
     *
     * NOTE: Signers should be ordered by their {signerId} to prevent duplications.
     */
    function scheduleMultisigner(
        address account,
        Mode mode,
        bytes calldata executionCalldata,
        bytes32 salt,
        bytes calldata signature
    ) public virtual returns (bytes32 operationId) {
        bytes32 hash = hashOperation(account, mode, executionCalldata, salt);
        (bytes[] memory signingSigners, bytes[] memory signatures) = abi.decode(signature, (bytes[], bytes[]));
        require(
            _validateNSignatures(account, hash, signingSigners, signatures) &&
                _validateThreshold(account, signingSigners),
            ERC7579MultisigExecutorInvalidSignatures()
        );

        // Schedule the operation
        (operationId, ) = _schedule(account, mode, executionCalldata, salt);
        return operationId;
    }

    /// @dev Adds the `newSigners` to those allowed to sign on behalf of the account.
    function _addSigners(address account, bytes[] memory newSigners) internal virtual {
        EnumerableSetExtended.BytesSet storage signerSet = _signers(account);

        for (uint256 i = 0; i < newSigners.length; i++) {
            bytes memory signer = newSigners[i];
            require(signer.length >= 20, ERC7579MultisigExecutorInvalidSigner(signer));
            require(signerSet.add(signer), ERC7579MultisigExecutorAlreadyExists(signer));
        }

        emit ERC7913SignersAdded(account, newSigners);
    }

    /// @dev Removes the `oldSigners` from the authorized signers for the account.
    function _removeSigners(address account, bytes[] memory oldSigners) internal virtual {
        EnumerableSetExtended.BytesSet storage signerSet = _signers(account);

        for (uint256 i = 0; i < oldSigners.length; i++) {
            bytes memory signer = oldSigners[i];
            require(signerSet.remove(signer), ERC7579MultisigExecutorNonexistentSigner(signer));
        }

        _validateReachableThreshold(account);
        emit ERC7913SignersRemoved(account, oldSigners);
    }

    /// @dev Sets the signatures `threshold` required to approve a multisignature operation.
    function _setThreshold(address account, uint256 newThreshold) internal virtual {
        _thresholdByAccount[account] = newThreshold;
        _validateReachableThreshold(account);
        emit ERC7913ThresholdSet(account, newThreshold);
    }

    /// @dev Validates the current threshold is reachable with the number of {signers}.
    function _validateReachableThreshold(address account) internal view virtual {
        uint256 totalSigners = _signers(account).length();
        uint256 currentThreshold = threshold(account);
        require(
            totalSigners >= currentThreshold,
            ERC7579MultisigExecutorUnreachableThreshold(totalSigners, currentThreshold)
        );
    }

    /**
     * @dev Validates the signatures using the signers and their corresponding signatures.
     * Returns whether the signers are authorized and the signatures are valid for the given hash.
     *
     * The signers must be ordered by their `signerId` to ensure no duplicates and to optimize
     * the verification process. The function will return `false` if the signers are not properly ordered.
     *
     * Requirements:
     *
     * * The `signatures` array must be at least the `signers` array's length.
     */
    function _validateNSignatures(
        address account,
        bytes32 hash,
        bytes[] memory signingSigners,
        bytes[] memory signatures
    ) internal view virtual returns (bool valid) {
        uint256 signersLength = signingSigners.length;
        for (uint256 i = 0; i < signersLength; i++) {
            if (!isSigner(account, signingSigners[i])) {
                return false;
            }
        }
        return hash.areValidNSignaturesNow(signingSigners, signatures, signerId);
    }

    /**
     * @dev Validates that the number of signers meets the {threshold} requirement.
     * Assumes the signers were already validated. See {_validateNSignatures} for more details.
     */
    function _validateThreshold(
        address account,
        bytes[] memory validatingSigners
    ) internal view virtual returns (bool) {
        return validatingSigners.length >= threshold(account);
    }
}
