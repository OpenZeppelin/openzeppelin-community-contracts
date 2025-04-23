// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {AbstractSigner} from "./AbstractSigner.sol";
import {ERC7913Utils} from "./ERC7913Utils.sol";
import {EnumerableSetExtended} from "../../utils/structs/EnumerableSetExtended.sol";
import {Calldata} from "@openzeppelin/contracts/utils/Calldata.sol";

/**
 * @dev Implementation of {AbstractSigner} using multiple ERC-7913 signers with a threshold-based
 * signature verification system.
 *
 * This contract allows managing a set of authorized signers and requires a minimum number of
 * signatures (threshold) to approve operations. It uses ERC-7913 formatted signers, which
 * concatenate a verifier address and a key: `verifier || key`.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyMultiSignerAccount is Account, MultiSignerERC7913, Initializable {
 *     constructor() EIP712("MyMultiSignerAccount", "1") {}
 *
 *     function initialize(bytes[] memory signers, uint256 threshold) public initializer {
 *         _addSigners(signers);
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
 * }
 * ```
 *
 * IMPORTANT: Failing to properly initialize the signers and threshold either during construction
 * (if used standalone) or during initialization (if used as a clone) may leave the contract
 * either front-runnable or unusable.
 */
abstract contract MultiSignerERC7913 is AbstractSigner {
    using EnumerableSetExtended for EnumerableSetExtended.BytesSet;
    using ERC7913Utils for bytes;

    /// @dev Emitted when signers are added.
    event ERC7913SignersAdded(bytes[] indexed signers);

    /// @dev Emitted when signers are removed.
    event ERC7913SignersRemoved(bytes[] indexed signers);

    /// @dev Emitted when the threshold is updated.
    event ThresholdSet(uint256 threshold);

    /// @dev The `signer` already exists.
    error MultiSignerERC7913AlreadyExists(bytes signer);

    /// @dev The `signer` does not exist.
    error MultiSignerERC7913NonexistentSigner(bytes signer);

    /// @dev The `signer` is less than 20 bytes long.
    error MultiERC7913InvalidSigner(bytes signer);

    /// @dev The `threshold` is unreachable given the number of `signers`.
    error MultiERC7913UnreachableThreshold(uint256 signers, uint256 threshold);

    EnumerableSetExtended.BytesSet private _signersSet;
    uint256 private _minSigners;

    /// @dev Returns the internal id of the `signer`.
    function signerId(bytes memory signer) public view virtual returns (bytes32) {
        return keccak256(signer);
    }

    /// @dev Returns the set of authorized signers.
    function _signers() internal view virtual returns (EnumerableSetExtended.BytesSet storage) {
        return _signersSet;
    }

    /// @dev Returns the minimum number of signers required to approve a multisignature operation.
    function _threshold() internal view virtual returns (uint256) {
        return _minSigners;
    }

    /// @dev Adds the `signers` to those allowed to sign on behalf of this contract. Internal version without access control.
    function _addSigners(bytes[] memory signers) internal virtual {
        for (uint256 i = 0; i < signers.length; i++) {
            bytes memory signer = signers[i];
            require(signer.length >= 20, MultiERC7913InvalidSigner(signer));
            require(_signersSet.add(signer), MultiSignerERC7913AlreadyExists(signer));
        }
        emit ERC7913SignersAdded(signers);
    }

    /// @dev Removes the `signers` from the authorized signers. Internal version without access control.
    function _removeSigners(bytes[] memory signers) internal virtual {
        for (uint256 i = 0; i < signers.length; i++) {
            bytes memory signer = signers[i];
            require(_signersSet.remove(signer), MultiSignerERC7913NonexistentSigner(signer));
        }
        _validateReachableThreshold();
        emit ERC7913SignersRemoved(signers);
    }

    /// @dev Sets the signatures `threshold` required to approve a multisignature operation. Internal version without access control.
    function _setThreshold(uint256 threshold_) internal virtual {
        _minSigners = threshold_;
        _validateReachableThreshold();
        emit ThresholdSet(threshold_);
    }

    /// @dev Validates the current threshold is reachable.
    function _validateReachableThreshold() internal view virtual {
        uint256 signers = _signers().length();
        uint256 threshold = _threshold();
        require(signers >= threshold, MultiERC7913UnreachableThreshold(signers, threshold));
    }

    /**
     * @dev Decodes, validates the signature and checks the signers are authorized.
     * See {_validateNSignatures} and {_validateThreshold} for more details.
     *
     * Example of signature encoding:
     *
     * ```solidity
     * // Encode signers (verifier || key)
     * bytes memory signer1 = abi.encodePacked(verifier1, key1);
     * bytes memory signer2 = abi.encodePacked(verifier2, key2);
     *
     * // Order signers by their id
     * if (keccak256(signer1) > keccak256(signer2)) {
     *     (signer1, signer2) = (signer2, signer1);
     *     (signature1, signature2) = (signature2, signature1);
     * }
     *
     * // Assign ordered signers and signatures
     * bytes[] memory signers = new bytes[](2);
     * bytes[] memory signatures = new bytes[](2);
     * signers[0] = signer1;
     * signatures[0] = signature1;
     * signers[1] = signer2;
     * signatures[1] = signature2;
     *
     * // Encode the multi signature
     * bytes memory signature = abi.encode(signers, signatures);
     * ```
     */
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        if (signature.length == 0) return false; // For ERC-7739 compatibility
        (bytes[] memory signers, bytes[] memory signatures) = abi.decode(signature, (bytes[], bytes[]));
        if (signers.length != signatures.length) return false;
        return _validateNSignatures(hash, signers, signatures) && _validateThreshold(signers);
    }

    /**
     * @dev Validates the signatures using the signers and their corresponding signatures.
     * Returns whether whether the signers are authorized and the signatures are valid for the given hash.
     *
     * IMPORTANT: For simplicity, this contract assumes that the signers are ordered by their {signerId} to
     * avoid duplication when iterating through the signers (i.e. `signerId(signer1) < signerId(signer2)`).
     * The function will return false if the signers are not ordered.
     *
     * Requirements:
     *
     * - The `signers` and `signatures` arrays must be of the same length.
     */
    function _validateNSignatures(
        bytes32 hash,
        bytes[] memory signers,
        bytes[] memory signatures
    ) internal view virtual returns (bool valid) {
        bytes32 currentSignerId = bytes32(0);

        uint256 signersLength = signers.length;
        for (uint256 i = 0; i < signersLength; i++) {
            // Signers must ordered by id to ensure no duplicates
            bytes memory signer = signers[i];
            bytes32 id = signerId(signer);
            if (
                currentSignerId >= id ||
                !_signers().contains(signer) ||
                !signer.isValidSignatureNow(hash, signatures[i])
            ) {
                return false;
            }

            currentSignerId = id;
        }

        return true;
    }

    /**
     * @dev Validates that the number of signers meets the {_threshold} requirement.
     * Assumes the signers were already validated. See {_validateNSignatures} for more details.
     */
    function _validateThreshold(bytes[] memory validatedSigners) internal view virtual returns (bool) {
        return validatedSigners.length >= _threshold();
    }
}
