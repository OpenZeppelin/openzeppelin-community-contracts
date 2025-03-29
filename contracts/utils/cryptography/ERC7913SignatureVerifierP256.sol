// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {P256} from "@openzeppelin/contracts/utils/cryptography/P256.sol";
import {IERC7913SignatureVerifier} from "../../interfaces/IERC7913.sol";

contract ERC7913SignatureVerifierP256 is IERC7913SignatureVerifier {
    function verify(bytes calldata key, bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        // Signature length may be 0x40 or 0x41.
        if (key.length == 0x40 && signature.length > 0x3f && signature.length < 0x42) {
            bytes32 qx = bytes32(key[0x00:0x20]);
            bytes32 qy = bytes32(key[0x20:0x40]);
            bytes32 r = bytes32(signature[0x00:0x20]);
            bytes32 s = bytes32(signature[0x20:0x40]);
            if (P256.verify(hash, r, s, qx, qy)) {
                return IERC7913SignatureVerifier.verify.selector;
            }
        }
        return 0xFFFFFFFF;
    }
}
