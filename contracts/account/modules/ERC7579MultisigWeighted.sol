// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC7579Multisig} from "./ERC7579Multisig.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSetExtended} from "../../utils/structs/EnumerableSetExtended.sol";

/**
 * @dev Extension of {ERC7579Multisig} that supports weighted signatures.
 *
 * This module extends the multisignature module to allow assigning different weights
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
abstract contract ERC7579MultisigWeighted is ERC7579Multisig {
    using EnumerableSetExtended for EnumerableSetExtended.BytesSet;

    // Mapping from account => signer => weight
    mapping(address account => mapping(bytes signer => uint256)) private _weights;

    // Invariant: sum(weights(account)) >= threshold(account)
    mapping(address account => uint256 totalWeight) private _totalWeight;

    /// @dev Emitted when a signer's weight is changed.
    event ERC7579MultisigWeightChanged(address indexed account, bytes indexed signer, uint256 weight);

    /// @dev Thrown when a signer's weight is invalid.
    error ERC7579MultisigInvalidWeight(bytes signer, uint256 weight);

    /// @dev Thrown when the arrays lengths don't match.
    error ERC7579MultisigMismatchedLength();

    /**
     * @dev Sets up the module's initial configuration when installed by an account.
     * Besides the standard delay and signer configuration, this can also include
     * signer weights.
     *
     * The initData should be encoded as:
     * `abi.encode(bytes[] signers, uint256 threshold, uint256[] weights)`
     *
     * If weights are not provided but signers are, all signers default to weight 1.
     *
     * NOTE: An account can only call onInstall once. If called directly by the account,
     * the signer will be set to the provided data. Future installations will behave as a no-op.
     */
    function onInstall(bytes calldata initData) public virtual override {
        bool installed = _signers(msg.sender).length() > 0;
        super.onInstall(initData);
        if (initData.length > 96 && !installed) {
            (bytes[] memory signers, , uint256[] memory weights) = abi.decode(initData, (bytes[], uint256, uint256[]));
            _setSignerWeights(msg.sender, signers, weights);
        }
    }

    /**
     * @dev Cleans up module's configuration when uninstalled from an account.
     * Clears all signers, weights, and total weights.
     *
     * See {ERC7579Multisig-onUninstall}.
     */
    function onUninstall(bytes calldata data) public virtual override {
        address account = msg.sender;

        bytes[] memory allSigners = signers(account);
        uint256 allSignersLength = allSigners.length;
        for (uint256 i = 0; i < allSignersLength; i++) {
            delete _weights[account][allSigners[i]];
        }
        delete _totalWeight[account];

        // Call parent implementation which will clear signers and threshold
        super.onUninstall(data);
    }

    /// @dev Gets the weight of a signer for a specific account. Returns 0 if the signer is not authorized.
    function signerWeight(address account, bytes memory signer) public view virtual returns (uint256) {
        return isSigner(account, signer) ? _signerWeight(account, signer) : 0;
    }

    /// @dev Gets the total weight of all signers for a specific account.
    function totalWeight(address account) public view virtual returns (uint256) {
        return _totalWeight[account]; // Doesn't need Math.max because it's incremented by the default 1 in `_addSigners`
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
        return Math.max(_weights[account][signer], 1);
    }

    /**
     * @dev Sets weights for multiple signers at once. Internal version without access control.
     *
     * Requirements:
     *
     * * `signers` and `weights` arrays must have the same length. Reverts with {ERC7579MultisigMismatchedLength} on mismatch.
     * * Each signer must exist in the set of authorized signers. Reverts with {ERC7579MultisigNonexistentSigner} if not.
     * * Each weight must be greater than 0. Reverts with {ERC7579MultisigInvalidWeight} if not.
     * * See {_validateReachableThreshold} for the threshold validation.
     *
     * Emits {ERC7579MultisigWeightChanged} for each signer.
     */
    function _setSignerWeights(address account, bytes[] memory signers, uint256[] memory newWeights) internal virtual {
        uint256 signersLength = signers.length;
        require(signersLength == newWeights.length, ERC7579MultisigMismatchedLength());
        uint256 oldWeight = _weightSigners(account, signers);

        for (uint256 i = 0; i < signersLength; i++) {
            bytes memory signer = signers[i];
            uint256 newWeight = newWeights[i];
            require(isSigner(account, signer), ERC7579MultisigNonexistentSigner(signer));
            require(newWeight > 0, ERC7579MultisigInvalidWeight(signer, newWeight));
        }

        _unsafeSetSignerWeights(account, signers, newWeights);
        _totalWeight[account] = totalWeight(account) - oldWeight + _weightSigners(account, signers);
        _validateReachableThreshold(account);
    }

    /**
     * @dev Override to add weight tracking. See {ERC7579Multisig-_addSigners}.
     * Each new signer has a default weight of 1.
     */
    function _addSigners(address account, bytes[] memory newSigners) internal virtual override {
        super._addSigners(account, newSigners);
        _totalWeight[account] += newSigners.length; // Default weight of 1 per signer.
    }

    /// @dev Override to handle weight tracking during removal. See {ERC7579Multisig-_removeSigners}.
    function _removeSigners(address account, bytes[] memory oldSigners) internal virtual override {
        uint256 removedWeight = _weightSigners(account, oldSigners);
        unchecked {
            // Can't overflow. Invariant: sum(weights) >= threshold
            _totalWeight[account] -= removedWeight;
        }
        _unsafeSetSignerWeights(account, oldSigners, new uint256[](oldSigners.length));
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
        require(weight >= currentThreshold, ERC7579MultisigUnreachableThreshold(weight, currentThreshold));
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

    /**
     * @dev Sets the `newWeights` for multiple `signers` without updating the {totalWeight} or
     * validating the threshold of `account`.
     *
     * Requirements:
     *
     * * The `newWeights` array must be at least as large as the `signers` array. Panics otherwise.
     *
     * Emits {ERC7579MultisigWeightChanged} for each signer.
     */
    function _unsafeSetSignerWeights(address account, bytes[] memory signers, uint256[] memory newWeights) private {
        uint256 signersLength = signers.length;
        for (uint256 i = 0; i < signersLength; i++) {
            _weights[account][signers[i]] = newWeights[i];
            emit ERC7579MultisigWeightChanged(account, signers[i], newWeights[i]);
        }
    }
}
