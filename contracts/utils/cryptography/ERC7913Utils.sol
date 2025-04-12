// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
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
        bytes calldata signer,
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool) {
        if (signer.length < 20) {
            return false;
        } else if (signer.length == 20) {
            return SignatureChecker.isValidSignatureNow(address(bytes20(signer)), hash, signature);
        } else {
            try IERC7913SignatureVerifier(address(bytes20(signer[0:20]))).verify(signer[20:], hash, signature) returns (
                bytes4 magic
            ) {
                return magic == IERC7913SignatureVerifier.verify.selector;
            } catch {
                return false;
            }
        }
    }
}
