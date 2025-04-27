// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {IERC7913SignatureVerifier} from "../../interfaces/IERC7913.sol";

/**
 * @dev Library that provides common ERC-7913 utility functions.
 *
 * This library extends the functionality of
 * https://docs.openzeppelin.com/contracts/5.x/api/utils#SignatureChecker[SignatureChecker]
 * to support signature verification for keys that do not have an Ethereum address of their own
 * as with ERC-1271.
 *
 * See https://eips.ethereum.org/EIPS/eip-7913[ERC-7913].
 */
library ERC7913Utils {
    using Bytes for bytes;

    /**
     * @dev Verifies a signature for a given signer and hash.
     *
     * The signer is a `bytes` object that is the concatenation of an address and optionally a key:
     * `verifier || key`. A signer must be at least 20 bytes long.
     *
     * Verification is done as follows:
     * - If `signer.length < 20`: verification fails
     * - If `signer.length == 20`: verification is done using {SignatureChecker}
     * - Otherwise: verification is done using {IERC7913SignatureVerifier}
     */
    function isValidSignatureNow(
        bytes memory signer,
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool) {
        if (signer.length < 20) {
            return false;
        } else if (signer.length == 20) {
            return SignatureChecker.isValidSignatureNow(address(bytes20(signer)), hash, signature);
        } else {
            (bool success, bytes memory result) = address(bytes20(signer)).staticcall(
                abi.encodeCall(IERC7913SignatureVerifier.verify, (signer.slice(20), hash, signature))
            );
            return (success &&
                result.length >= 32 &&
                abi.decode(result, (bytes32)) == bytes32(IERC7913SignatureVerifier.verify.selector));
        }
    }

    /**
     * @dev Verifies multiple `signatures` for a given hash using a set of `signers`.
     *
     * The signers must be ordered by their `signerId` to ensure no duplicates and to optimize
     * the verification process. The function will return `false` if the signers are not properly ordered.
     *
     * Requirements:
     *
     * * The `signatures` array must be at least the  `signers` array's length.
     *
     * NOTE: The `signerId` function argument must be deterministic and should not manipulate
     * memory state directly and should follow Solidity memory safety rules to avoid unexpected behavior.
     */
    function areValidNSignaturesNow(
        bytes32 hash,
        bytes[] memory signers,
        bytes[] memory signatures,
        function(bytes memory) view returns (bytes32) signerId
    ) internal view returns (bool) {
        bytes32 currentSignerId = bytes32(0);

        uint256 signersLength = signers.length;
        for (uint256 i = 0; i < signersLength; i++) {
            bytes memory signer = signers[i];
            // Signers must ordered by id to ensure no duplicates
            bytes32 id = signerId(signer);
            if (currentSignerId >= id || !isValidSignatureNow(signer, hash, signatures[i])) {
                return false;
            }

            currentSignerId = id;
        }

        return true;
    }

    /// @dev Overload of {areValidNSignaturesNow} that uses the `keccak256` as the `signerId` function.
    function areValidNSignaturesNow(
        bytes32 hash,
        bytes[] memory signers,
        bytes[] memory signatures
    ) internal view returns (bool) {
        return areValidNSignaturesNow(hash, signers, signatures, _keccak256);
    }

    /// @dev Computes the keccak256 hash of the given data.
    function _keccak256(bytes memory data) private pure returns (bytes32) {
        return keccak256(data);
    }
}
