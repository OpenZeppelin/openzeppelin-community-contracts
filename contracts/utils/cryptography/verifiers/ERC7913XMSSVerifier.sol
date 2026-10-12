// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC7913SignatureVerifier} from "@openzeppelin/contracts/interfaces/IERC7913.sol";
import {XMSS} from "../XMSS.sol";

/**
 * @dev ERC-7913 signature verifier for XMSS-style hash-based signatures. See {XMSS}.
 *
 * The tree height is fixed per deployment, so every key verified by an instance has the same capacity of
 * 2^{height} signatures. The key is the 32-byte concatenation `seed || root`, so the ERC-7913 signer is
 * `verifier || seed || root`.
 *
 * Verification is stateless and composes with any ERC-7913 consumer (e.g. `SignerERC7913`, `MultiSignerERC7913`
 * or the ERC-7579 multisig modules). Combining it with a signer of a different scheme in a multisig (e.g. a
 * 2-of-2 with an ECDSA signer) requires an attacker to break both schemes.
 *
 * IMPORTANT: Each leaf of the tree must sign at most one message. The signing software is responsible for tracking
 * the next unused leaf; this contract accepts any valid signature from any leaf. See {XMSS}.
 */
contract ERC7913XMSSVerifier is IERC7913SignatureVerifier {
    uint8 private immutable _height;

    /// @dev The `height` exceeds {XMSS-MAX_HEIGHT}.
    error ERC7913XMSSVerifierInvalidHeight(uint8 height);

    constructor(uint8 height_) {
        require(height_ <= XMSS.MAX_HEIGHT, ERC7913XMSSVerifierInvalidHeight(height_));
        _height = height_;
    }

    /// @dev Height of the trees verified by this instance.
    function height() public view virtual returns (uint8) {
        return _height;
    }

    /**
     * @dev Verifies `signature` as an XMSS signature of `hash` for `key`.
     *
     * The key is the 32-byte packed encoding `seed (16 bytes) || root (16 bytes)`. See {XMSS} for the signature
     * encoding. Returns `0xffffffff` for keys of a different length.
     */
    function verify(
        bytes calldata key,
        bytes32 hash,
        bytes calldata signature
    ) public view virtual override returns (bytes4) {
        return
            key.length == 32 && XMSS.verify(bytes16(key[0:16]), bytes16(key[16:32]), height(), hash, signature)
                ? IERC7913SignatureVerifier.verify.selector
                : bytes4(0xffffffff);
    }
}
