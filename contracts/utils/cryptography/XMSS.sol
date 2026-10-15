// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/**
 * @dev Verification of XMSS-style hash-based signatures instantiated with `keccak256`.
 *
 * A key commits to 2^`height` WOTS+ one-time keys arranged as the leaves of a Merkle tree. The public key is the
 * pair (`seed`, `root`), where `seed` is a public random value that separates the hashes of different keys. Each
 * signature is a WOTS+ signature produced by one leaf, together with the leaf index and the Merkle path from that
 * leaf to the root.
 *
 * The construction follows https://www.rfc-editor.org/rfc/rfc8391[RFC 8391] (XMSS) for the tree and the WOTS+ chains,
 * with the "simple" tweakable hash of SPHINCS+ (no bitmasks) and `keccak256` truncated to `N` bytes as the hash
 * function. It is NOT interoperable with RFC 8391 or NIST SP 800-208 implementations, which use SHA-2 or SHAKE.
 *
 * Parameters: `N = 16` bytes, `W = 16`, `LEN = 35` chains (`LEN1 = 32` message digits and `LEN2 = 3` checksum
 * digits). The tree height is chosen by the caller, up to `MAX_HEIGHT`.
 *
 * Signature encoding (packed):
 *
 * ```
 * | leaf index (4 bytes) | randomizer (N bytes) | WOTS+ chain values (LEN * N bytes) | authentication path (height * N bytes) |
 * ```
 *
 * Hashing (`T` is `keccak256` truncated to its first `N` bytes, `ADRS` is a 32-byte word described in {_adrs}):
 *
 * * Message digest: `T(seed || ADRS(MESSAGE, leaf) || root || randomizer || hash)`
 * * Chain step `j` of chain `i`: `T(seed || ADRS(WOTS_HASH, leaf, i, j) || x)`
 * * WOTS+ public key: `T(seed || ADRS(WOTS_PK, leaf) || end_0 || ... || end_34)`
 * * Tree node at `level` (1 for the parents of the leaves) and `index`: `T(seed || ADRS(TREE, index, level) || left || right)`
 *
 * IMPORTANT: Verification is stateless. Security relies on the signer never producing two signatures with the same
 * leaf, which is a property the signing software must preserve (e.g. by persisting the next leaf index before
 * releasing a signature). Two signatures over different messages with the same leaf allow forging signatures for
 * that leaf.
 */
library XMSS {
    /// @dev Size in bytes of every hash value (seed, root, chain values and tree nodes).
    uint256 internal constant N = 16;

    /// @dev Winternitz parameter. Each chain has `W - 1` hash steps.
    uint256 internal constant W = 16;

    /// @dev Number of base-`W` digits of the message digest.
    uint256 internal constant LEN1 = 32;

    /// @dev Number of base-`W` digits of the checksum.
    uint256 internal constant LEN2 = 3;

    /// @dev Total number of WOTS+ chains.
    uint256 internal constant LEN = LEN1 + LEN2;

    /// @dev Maximum tree height. Leaf indices are encoded as `uint32`.
    uint8 internal constant MAX_HEIGHT = 32;

    uint256 private constant _RANDOMIZER_OFFSET = 4;
    uint256 private constant _CHAINS_OFFSET = _RANDOMIZER_OFFSET + N;
    uint256 private constant _AUTH_PATH_OFFSET = _CHAINS_OFFSET + LEN * N;

    uint256 private constant _TYPE_WOTS_HASH = 0;
    uint256 private constant _TYPE_WOTS_PK = 1;
    uint256 private constant _TYPE_TREE = 2;
    uint256 private constant _TYPE_MESSAGE = 3;

    /// @dev Length in bytes of a signature for a tree of the given `height`.
    function signatureLength(uint8 height) internal pure returns (uint256) {
        return _AUTH_PATH_OFFSET + uint256(height) * N;
    }

    /**
     * @dev Returns whether `signature` is a valid signature of `hash` for the key (`seed`, `root`) of a tree with
     * the given `height`.
     *
     * Returns false if `height` exceeds `MAX_HEIGHT`, if the signature length doesn't match {signatureLength} or if
     * the leaf index is outside the tree.
     */
    function verify(
        bytes16 seed,
        bytes16 root,
        uint8 height,
        bytes32 hash,
        bytes calldata signature
    ) internal pure returns (bool) {
        if (height > MAX_HEIGHT || signature.length != signatureLength(height)) return false;

        uint32 leaf = uint32(bytes4(signature[0:4]));
        if (uint256(leaf) >> height != 0) return false;

        assembly ("memory-safe") {
            seed := and(seed, not(sub(shl(128, 1), 1))) // clean low bits before hashing
            root := and(root, not(sub(shl(128, 1), 1)))
        }

        bytes16 digest = messageDigest(seed, root, leaf, _readNode(signature, _RANDOMIZER_OFFSET), hash);
        bytes16 node = _wotsPublicKey(seed, leaf, digest, signature);
        return _computeRoot(seed, height, leaf, node, signature) == root;
    }

    /**
     * @dev Digest signed by the WOTS+ key of `leaf`. Binds the signed `hash` to the key and leaf, randomized by the
     * signer-provided `randomizer`.
     */
    function messageDigest(
        bytes16 seed,
        bytes16 root,
        uint32 leaf,
        bytes16 randomizer,
        bytes32 hash
    ) internal pure returns (bytes16 digest) {
        uint256 adrs = _adrs(_TYPE_MESSAGE, leaf, 0, 0);
        assembly ("memory-safe") {
            let mask := not(sub(shl(128, 1), 1))
            let ptr := mload(0x40)
            mstore(ptr, and(seed, mask))
            mstore(add(ptr, 0x10), adrs)
            mstore(add(ptr, 0x30), and(root, mask))
            mstore(add(ptr, 0x40), and(randomizer, mask))
            mstore(add(ptr, 0x50), hash)
            digest := and(keccak256(ptr, 0x70), mask)
        }
    }

    /// @dev Recovers the WOTS+ public key of `leaf` from the chain values in `signature`.
    function _wotsPublicKey(
        bytes16 seed,
        uint32 leaf,
        bytes16 digest,
        bytes calldata signature
    ) private pure returns (bytes16 publicKey) {
        // seed || ADRS || LEN chain ends, plus 16 bytes of padding for the last 32-byte write
        bytes memory buffer = new bytes(0x30 + LEN * N + 0x10);

        uint256 checksum = 0;
        for (uint256 i = 0; i < LEN; ++i) {
            uint256 digit;
            if (i < LEN1) {
                digit = (uint128(digest) >> (124 - 4 * i)) & 0xf; // most significant digit first
                checksum += W - 1 - digit;
            } else {
                digit = (checksum >> (4 * (LEN - 1 - i))) & 0xf;
            }

            bytes16 end = _chain(
                seed,
                _adrs(_TYPE_WOTS_HASH, leaf, i, 0),
                _readNode(signature, _CHAINS_OFFSET + i * N),
                digit
            );
            assembly ("memory-safe") {
                mstore(add(buffer, add(0x50, mul(i, 0x10))), end)
            }
        }

        uint256 pkAdrs = _adrs(_TYPE_WOTS_PK, leaf, 0, 0);
        uint256 preimageLength = 0x30 + LEN * N;
        assembly ("memory-safe") {
            mstore(add(buffer, 0x20), seed)
            mstore(add(buffer, 0x30), pkAdrs)
            publicKey := and(keccak256(add(buffer, 0x20), preimageLength), not(sub(shl(128, 1), 1)))
        }
    }

    /// @dev Computes the root of the tree from the leaf `node` and the authentication path in `signature`.
    function _computeRoot(
        bytes16 seed,
        uint8 height,
        uint32 leaf,
        bytes16 node,
        bytes calldata signature
    ) private pure returns (bytes16) {
        uint256 index = leaf;
        for (uint256 level = 0; level < height; ++level) {
            bytes16 sibling = _readNode(signature, _AUTH_PATH_OFFSET + level * N);
            uint256 adrs = _adrs(_TYPE_TREE, index >> 1, level + 1, 0);
            node = index & 1 == 0 ? _hashNode(seed, adrs, node, sibling) : _hashNode(seed, adrs, sibling, node);
            index >>= 1;
        }
        return node;
    }

    /**
     * @dev Address word that separates every hash in the scheme:
     * `type (8 bits) || zeros (56 bits) || a (64 bits) || b (64 bits) || c (64 bits)`.
     *
     * * `WOTS_HASH`: `a` is the leaf, `b` the chain and `c` the step within the chain.
     * * `WOTS_PK` and `MESSAGE`: `a` is the leaf.
     * * `TREE`: `a` is the node index within its level and `b` the level.
     */
    function _adrs(uint256 kind, uint256 a, uint256 b, uint256 c) private pure returns (uint256) {
        return (kind << 248) | (a << 128) | (b << 64) | c;
    }

    /**
     * @dev Completes a WOTS+ chain from position `start`: applies `x = T(seed || adrs + j || x)` for `j` in
     * `[start, W - 1)`. Expects `seed` and `x` with clean low bits, and the step field of `adrs` set to zero.
     */
    function _chain(bytes16 seed, uint256 adrs, bytes16 x, uint256 start) private pure returns (bytes16 result) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            let mask := not(sub(shl(128, 1), 1))
            mstore(ptr, seed) // the ADRS writes below only overwrite bytes [16, 48)
            result := x
            for {
                let j := start
            } lt(j, 15) {
                j := add(j, 1)
            } {
                mstore(add(ptr, 0x10), or(adrs, j))
                mstore(add(ptr, 0x30), result)
                result := and(keccak256(ptr, 0x40), mask)
            }
        }
    }

    /// @dev `T(seed || adrs || left || right)`. Expects `seed`, `left` and `right` with clean low bits.
    function _hashNode(bytes16 seed, uint256 adrs, bytes16 left, bytes16 right) private pure returns (bytes16 result) {
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, seed)
            mstore(add(ptr, 0x10), adrs)
            mstore(add(ptr, 0x30), left)
            mstore(add(ptr, 0x40), right)
            result := and(keccak256(ptr, 0x50), not(sub(shl(128, 1), 1)))
        }
    }

    /// @dev Reads the `N` bytes at `offset` in `signature`, with clean low bits. Assumes the length was checked.
    function _readNode(bytes calldata signature, uint256 offset) private pure returns (bytes16 result) {
        assembly ("memory-safe") {
            result := and(calldataload(add(signature.offset, offset)), not(sub(shl(128, 1), 1)))
        }
    }
}
