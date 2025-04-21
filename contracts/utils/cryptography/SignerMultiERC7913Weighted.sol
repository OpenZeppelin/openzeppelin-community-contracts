// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignerMultiERC7913} from "./SignerMultiERC7913.sol";
import {EnumerableSetExtended} from "../../utils/structs/EnumerableSetExtended.sol";

/**
 * @dev Extension of {SignerMultiERC7913} that supports weighted signatures.
 *
 * This contract allows assigning different weights to each signer, enabling more
 * flexible governance schemes. For example, some signers could have higher weight
 * than others, allowing for weighted voting or prioritized authorization.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyWeightedMultiSignerAccount is Account, SignerMultiERC7913Weighted, Initializable {
 *     constructor() EIP712("MyWeightedMultiSignerAccount", "1") {}
 *
 *     function initialize(bytes[] memory signers, uint256[] memory weights, uint256 threshold) public initializer {
 *         _addSigners(signers);
 *         _setSignerWeights(signers, weights);
 *         _setThreshold(threshold);
 *     }
 *
 *     function addSigners(bytes[] memory signers) public onlyEntryPointOrSelf {
 *         _addSigners(signers);
 *     }
 *
 *     function removeSigners(bytes[] memory signers) public onlyEntryPointOrSelf {
 *         _removeSigners(signers);
 *     }
 *
 *     function setThreshold(uint256 threshold) public onlyEntryPointOrSelf {
 *         _setThreshold(threshold);
 *     }
 *
 *     function setSignerWeights(bytes[] memory signers, uint256[] memory weights) public onlyEntryPointOrSelf {
 *         _setSignerWeights(signers, weights);
 *     }
 * }
 * ```
 *
 * IMPORTANT: When setting a threshold value, ensure it matches the scale used for signer weights.
 * For example, if signers have weights like 1, 2, or 3, then a threshold of 4 would require at
 * least two signers (e.g., one with weight 1 and one with weight 3). See {signerWeight}.
 */
abstract contract SignerMultiERC7913Weighted is SignerMultiERC7913 {
    using EnumerableSetExtended for EnumerableSetExtended.BytesSet;

    // Mapping from signer ID to weight
    mapping(bytes32 signedId => uint256) private _weights;

    /// @dev Emitted when a signer's weight is changed.
    event ERC7913SignerWeightChanged(bytes indexed signer, uint256 weight);

    /// @dev Emitted when a signer's weight is invalid.
    error MultiERC7913WeightedInvalidWeight(bytes signer, uint256 weight);

    error MultiERC7913WeightedMismatchedLength();

    /// @dev Gets the weight of a signer. Returns 1 if not explicitly set.
    function signerWeight(bytes memory signer) public view virtual returns (uint256) {
        return Math.max(_weights[signerId(signer)], 1);
    }

    /**
     * @dev Sets weights for multiple signers at once. Internal version without access control.
     *
     * Requirements:
     *
     * - `signers` and `weights` arrays must have the same length. Reverts with {MultiERC7913WeightedMismatchedLength} on mismatch.
     * - Each signer must exist in the set of authorized signers. Reverts with {MultiERC7913SignerNonexistentSigner} if not.
     * - Each weight must be greater than 0. Reverts with {MultiERC7913WeightedInvalidWeight} if not.
     */
    function _setSignerWeights(bytes[] memory signers, uint256[] memory weights) internal virtual {
        require(signers.length == weights.length, MultiERC7913WeightedMismatchedLength());

        for (uint256 i = 0; i < signers.length; i++) {
            bytes memory signer = signers[i];
            uint256 weight = weights[i];
            require(_signers().contains(signer), MultiERC7913SignerNonexistentSigner(signer));
            require(weight > 0, MultiERC7913WeightedInvalidWeight(signer, weight));

            _weights[signerId(signer)] = weight;
            emit ERC7913SignerWeightChanged(signer, weight);
        }

        _validateReachableThreshold();
    }

    /// @dev Sets the threshold for the multisignature operation. Internal version without access control.
    function _validateReachableThreshold() internal view virtual override {
        // This override intentionally does not call `super._validateReachableThreshold` since that would
        // perform a comparison of `signers.length >= _threshold`, which is the less-weight per signer
        // scenario. This would cause a duplicated and unnecessary SLOAD. Since `_validateReachableThreshold` is
        // a `view` function, there are no state changes that we would miss by not calling super.
        require(
            _weightSigners(_signers().values()) >= _threshold(), // TODO: Should there be a max signers?
            MultiERC7913UnreachableThreshold(_signers().length(), _threshold())
        );
    }

    /// @dev Overrides the threshold validation to use signer weights.
    function _validateThreshold(bytes[] memory signers) internal view virtual override returns (bool) {
        // This override intentionally does not call `super._validateThreshold` since that would
        // perform a comparison of `signers.length >= _threshold`, which is the less-weight per signer
        // scenario. This would cause a duplicated and unnecessary SLOAD. Since `_validateThreshold` is
        // a `view` function, there are no state changes that we would miss by not calling super.
        return _weightSigners(signers) >= _threshold(); /* || super._validateThreshold(signers) */
    }

    /// @dev Calculates the total weight of a set of signers.
    function _weightSigners(bytes[] memory signers) internal view virtual returns (uint256) {
        uint256 totalWeight = 0;
        uint256 signersLength = signers.length;
        for (uint256 i = 0; i < signersLength; i++) {
            totalWeight += signerWeight(signers[i]);
        }
        return totalWeight;
    }
}
