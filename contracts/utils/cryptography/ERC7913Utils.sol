// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {IERC7913SignatureVerifier} from "../../interfaces/IERC7913.sol";

library ERC7913Utils {
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
            try
                IERC7913SignatureVerifier(address(bytes20(signer))).verify(Bytes.slice(signer, 20), hash, signature)
            returns (bytes4 magic) {
                return magic == IERC7913SignatureVerifier.verify.selector;
            } catch {
                return false;
            }
        }
    }

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
