// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC7579MultisigExecutor} from "./ERC7579MultisigExecutor.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSetExtended} from "../../utils/structs/EnumerableSetExtended.sol";

/**
 * @dev Extension of {ERC7579MultisigExecutor} that supports weighted signatures.
 *
 * This module extends the multisignature executor to allow assigning different weights
 * to each signer, enabling more flexible governance schemes. For example, some guardians
 * could have higher weight than others, allowing for weighted voting or prioritized authorization.
 *
 * Example use case:
 *
 * A smart account with this module installed can schedule social recovery operations
 * after obtaining approval from guardians with sufficient total weight (e.g., requiring
 * a total weight of 10, with 3 guardians weighted as 5, 3, and 2), and then execute them
 * after the time delay has passed.
 *
 * IMPORTANT: When setting a threshold value, ensure it matches the scale used for signer weights.
 * For example, if signers have weights like 1, 2, or 3, then a threshold of 4 would require
 * signatures with a total weight of at least 4 (e.g., one with weight 1 and one with weight 3).
 */
contract ERC7579MultisigWeightedExecutor is ERC7579MultisigExecutor {
    using EnumerableSetExtended for EnumerableSetExtended.BytesSet;

    // Mapping from account => signerId => weight
    mapping(address account => mapping(bytes32 signerId => uint256 weight)) private _weightsByAccount;

    // Invariant: sum(weights(account)) >= threshold(account)
    mapping(address account => uint256 totalWeight) private _totalWeightByAccount;

    /// @dev Emitted when a signer's weight is changed.
    event ERC7913SignerWeightChanged(address indexed account, bytes indexed signer, uint256 weight);

    /// @dev Thrown when a signer's weight is invalid.
    error ERC7579MultisigExecutorInvalidWeight(bytes signer, uint256 weight);

    /// @dev Thrown when the arrays lengths don't match.
    error ERC7579MultisigExecutorMismatchedLength();

    /**
     * @dev Sets up the module's initial configuration when installed by an account.
     * Besides the standard delay and signer configuration, this can also include
     * signer weights.
     *
     * The initData should be encoded as:
     * `abi.encode(uint32 initialDelay, bytes[] signers, uint256 threshold, uint256[] weights)`
     *
     * If weights are not provided but signers are, all signers default to weight 1.
     */
    function onInstall(bytes calldata initData) public virtual override {
        super.onInstall(initData);

        (, bytes[] memory signers, uint256 threshold, uint256[] memory weights) = abi.decode(
            initData,
            (uint32, bytes[], uint256, uint256[])
        );

        _addSigners(msg.sender, signers);
        _setSignerWeights(msg.sender, signers, weights);
        _setThreshold(msg.sender, threshold);
    }

    /**
     * @dev Cleans up module's configuration when uninstalled from an account.
     * Clears all signers, weights, and total weights.
     *
     * See {ERC7579MultisigExecutor-onUninstall}.
     */
    function onUninstall(bytes calldata data) public virtual override {
        address account = msg.sender;

        bytes[] memory allSigners = signers(account);
        for (uint256 i = 0; i < allSigners.length; i++) {
            delete _weightsByAccount[account][signerId(allSigners[i])];
        }
        delete _totalWeightByAccount[account];

        // Call parent implementation which will clear signers and threshold
        super.onUninstall(data);
    }

    /// @dev Gets the weight of a signer for a specific account. Returns 0 if the signer is not authorized.
    function signerWeight(address account, bytes memory signer) public view virtual returns (uint256) {
        return isSigner(account, signer) ? _signerWeight(account, signer) : 0;
    }

    /// @dev Gets the total weight of all signers for a specific account.
    function totalWeight(address account) public view virtual returns (uint256) {
        return Math.max(_totalWeightByAccount[account], _signers(account).length());
    }

    /**
     * @dev Sets weights for signers for the calling account.
     * Can only be called by the account itself.
     */
    function setSignerWeights(bytes[] memory signers, uint256[] memory weights) public virtual {
        _setSignerWeights(msg.sender, signers, weights);
    }

    /**
     * @dev Gets the weight of the current signer. Returns 1 if not explicitly set.
     * This internal function doesn't check if the signer is authorized.
     */
    function _signerWeight(address account, bytes memory signer) internal view virtual returns (uint256) {
        return Math.max(_weightsByAccount[account][signerId(signer)], 1);
    }

    /**
     * @dev Sets weights for multiple signers at once. Internal version without access control.
     *
     * Requirements:
     *
     * - `signers` and `weights` arrays must have the same length.
     * - Each signer must exist in the set of authorized signers.
     * - Each weight must be greater than 0.
     */
    function _setSignerWeights(address account, bytes[] memory signers, uint256[] memory newWeights) internal virtual {
        require(signers.length == newWeights.length, ERC7579MultisigExecutorMismatchedLength());

        uint256 cachedTotalWeight = _totalWeightByAccount[account];
        for (uint256 i = 0; i < signers.length; i++) {
            bytes memory signer = signers[i];
            uint256 newWeight = newWeights[i];
            require(isSigner(account, signer), ERC7579MultisigExecutorNonexistentSigner(signer));
            require(newWeight > 0, ERC7579MultisigExecutorInvalidWeight(signer, newWeight));

            uint256 oldWeight = _signerWeight(account, signer);
            _weightsByAccount[account][signerId(signer)] = newWeight;
            cachedTotalWeight = (cachedTotalWeight + newWeight - oldWeight);
            emit ERC7913SignerWeightChanged(account, signer, newWeight);
        }

        _totalWeightByAccount[account] = cachedTotalWeight;
        _validateReachableThreshold(account);
    }

    /**
     * @dev Override to add weight tracking. See {ERC7579MultisigExecutor-_addSigners}.
     * Each new signer has a default weight of 1.
     */
    function _addSigners(address account, bytes[] memory newSigners) internal virtual override {
        super._addSigners(account, newSigners);
        _totalWeightByAccount[account] += newSigners.length; // Default weight of 1 per signer
    }

    /// @dev Override to handle weight tracking during removal. See {ERC7579MultisigExecutor-_removeSigners}.
    function _removeSigners(address account, bytes[] memory oldSigners) internal virtual override {
        uint256 removedWeight = _weightSigners(account, oldSigners);
        _totalWeightByAccount[account] -= removedWeight;

        for (uint256 i = 0; i < oldSigners.length; i++) {
            delete _weightsByAccount[account][signerId(oldSigners[i])];
            emit ERC7913SignerWeightChanged(account, oldSigners[i], 0);
        }

        super._removeSigners(account, oldSigners);
    }

    /**
     * @dev Override to validate threshold against total weight instead of signer count.
     *
     * NOTE: This function intentionally does not call `super._validateReachableThreshold` because the base implementation
     * assumes each signer has a weight of 1, which is a subset of this weighted implementation. Consider that multiple
     * implementations of this function may exist in the contract, so important side effects may be missed
     * depending on the linearization order.
     */
    function _validateReachableThreshold(address account) internal view virtual override {
        uint256 weight = totalWeight(account);
        uint256 currentThreshold = threshold(account);
        require(weight >= currentThreshold, ERC7579MultisigExecutorUnreachableThreshold(weight, currentThreshold));
    }

    /**
     * @dev Validates that the total weight of signers meets the {threshold} requirement.
     * Overrides the base implementation to use weights instead of count.
     *
     * NOTE: This function intentionally does not call `super._validateThreshold` because the base implementation
     * assumes each signer has a weight of 1, which is incompatible with this weighted implementation.
     */
    function _validateThreshold(
        address account,
        bytes[] memory validatingSigners
    ) internal view virtual override returns (bool) {
        uint256 totalSigningWeight = _weightSigners(account, validatingSigners);
        return totalSigningWeight >= threshold(account);
    }

    /// @dev Calculates the total weight of a set of signers.
    function _weightSigners(address account, bytes[] memory signers) internal view virtual returns (uint256) {
        uint256 weight = 0;
        uint256 signersLength = signers.length;
        for (uint256 i = 0; i < signersLength; i++) {
            weight += signerWeight(account, signers[i]);
        }
        return weight;
    }
}
