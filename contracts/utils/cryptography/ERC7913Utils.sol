// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {IERC7913SignatureVerifier} from "../../interfaces/IERC7913.sol";

/**
 * @dev Helper library to verify key signatures following the ERC-7913 standard, with fallback to ECDSA and ERC-1271
 * when the signer's key is empty (as specified in ERC-7913)
 */
library ERC7913Utils {
    using Bytes for bytes;
    /**
     * @dev Checks if a signature is valid for a given signer and data hash. The signer is interpreted following
     * ERC-7913:
     * * If the signer's key is not empty the signature is verified using the signer's verifier ERC-7913 interface.
     * * Otherwise, the signature is verified using the `SignatureChecker` library, which supports both ECDSA and
     *   ERC-1271 signature verification
     *
     * NOTE: Unlike ECDSA signatures, contract signatures are revocable, and the outcome of this function can thus
     * change through time. It could return true at block N and false at block N+1 (or the opposite).
     */
    function isValidSignatureNow(
        bytes memory signer,
        bytes32 hash,
        bytes calldata signature
    ) internal view returns (bool) {
        if (signer.length < 20) {
            return false;
        } else if (signer.length == 20) {
            return SignatureChecker.isValidSignatureNow(address(bytes20(signer)), hash, signature);
        } else {
            try IERC7913SignatureVerifier(address(bytes20(signer))).verify(signer.slice(20), hash, signature) returns (
                bytes4 magic
            ) {
                return magic == IERC7913SignatureVerifier.verify.selector;
            } catch {
                return false;
            }
        }
    }

    /**
     * @dev Checks if a signature is valid for a given signer and data hash. The signer is interpreted following
     * ERC-7913:
     * * If the signer's key is not empty the signature is verified using the signer's verifier ERC-7913 interface.
     * * Otherwise, the signature is verified using the `SignatureChecker` library, which supports both ECDSA and
     *   ERC-1271 signature verification
     *
     * NOTE: Unlike ECDSA signatures, contract signatures are revocable, and the outcome of this function can thus
     * change through time. It could return true at block N and false at block N+1 (or the opposite).
     */
    function isValidSignatureNowCalldata(
        bytes calldata signer,
        bytes32 hash,
        bytes calldata signature
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
