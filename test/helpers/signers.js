const {
  assertArgument,
  dataLength,
  toBigInt,
  AbiCoder,
  hexlify,
  keccak256,
  randomBytes,
  solidityPacked,
  toBeHex,
} = require('ethers');

class ZKEmailSigningKey {
  #domainName;
  #publicKeyHash;
  #emailNullifier;
  #accountSalt;

  constructor(domainName, publicKeyHash, emailNullifier, accountSalt) {
    this.#domainName = domainName;
    this.#publicKeyHash = publicKeyHash;
    this.#emailNullifier = emailNullifier;
    this.#accountSalt = accountSalt;
    this.SIGN_HASH_COMMAND = 'signHash';
  }

  get domainName() {
    return this.#domainName;
  }

  get publicKeyHash() {
    return this.#publicKeyHash;
  }

  get emailNullifier() {
    return this.#emailNullifier;
  }

  get accountSalt() {
    return this.#accountSalt;
  }

  sign(digest /*: BytesLike*/ /*: Signature*/) {
    assertArgument(dataLength(digest) === 32, 'invalid digest length', 'digest', digest);

    const timestamp = Math.floor(Date.now() / 1000);
    const command = this.SIGN_HASH_COMMAND + ' ' + toBigInt(digest).toString();
    const isCodeExist = true;

    // Create valid Groth16 proof that matches ZKEmailGroth16VerifierMock expectations
    const pA = [1n, 2n];
    const pB = [
      [3n, 4n],
      [5n, 6n],
    ];
    const pC = [7n, 8n];
    const validProof = AbiCoder.defaultAbiCoder().encode(['uint256[2]', 'uint256[2][2]', 'uint256[2]'], [pA, pB, pC]);

    // Encode the EmailProof as the signature
    return {
      serialized: AbiCoder.defaultAbiCoder().encode(
        ['string', 'bytes32', 'uint256', 'string', 'bytes32', 'bytes32', 'bool', 'bytes'],
        [
          this.#domainName,
          this.#publicKeyHash,
          timestamp,
          command,
          this.#emailNullifier,
          this.#accountSalt,
          isCodeExist,
          validProof,
        ],
      ),
    };
  }
}

// Reference signer for `XMSS.sol` (N = 16, W = 16, LEN = 35, keccak256 truncated to N bytes)
const XMSS_W = 16;
const XMSS_LEN1 = 32;
const XMSS_LEN = 35;
const XMSS_TYPE = { WOTS_HASH: 0n, WOTS_PK: 1n, TREE: 2n, MESSAGE: 3n, WOTS_SK: 4n }; // WOTS_SK is only used offchain

const xmssAdrs = (kind, a = 0n, b = 0n, c = 0n) =>
  toBeHex((kind << 248n) | (BigInt(a) << 128n) | (BigInt(b) << 64n) | BigInt(c), 32);
const xmssHash = (...parts) => keccak256('0x' + parts.map(part => part.slice(2)).join('')).slice(0, 34);

function xmssDigits(digest) {
  const value = toBigInt(digest);
  const digits = [];
  let checksum = 0;
  for (let i = 0; i < XMSS_LEN1; ++i) {
    const digit = Number((value >> BigInt(124 - 4 * i)) & 0xfn);
    digits.push(digit);
    checksum += XMSS_W - 1 - digit;
  }
  digits.push((checksum >> 8) & 0xf, (checksum >> 4) & 0xf, checksum & 0xf);
  return digits;
}

class XMSSSigningKey {
  #skSeed;
  #nextLeaf = 0;

  /**
   * Generates every leaf of a tree of the given `height`. Expensive (2^height * 525 hashes).
   *
   * With `sparse: true`, only leaf 0 is a real WOTS+ key and the rest of the tree is random. The resulting key can sign
   * exactly once, which is enough to measure verification cost for large heights.
   */
  constructor(height, { seed = hexlify(randomBytes(16)), skSeed = hexlify(randomBytes(32)), sparse = false } = {}) {
    this.height = height;
    this.seed = seed;
    this.#skSeed = skSeed;
    this.capacity = sparse ? 1 : 2 ** height;

    const leaves = sparse
      ? [this.#wotsPublicKey(0)]
      : Array.from({ length: 2 ** height }, (_, i) => this.#wotsPublicKey(i));
    this.levels = [leaves];
    for (let level = 1; level <= height; ++level) {
      const below = this.levels[level - 1];
      const nodes = [];
      for (let index = 0; index < 2 ** (height - level); ++index) {
        const left = (below[2 * index] ??= hexlify(randomBytes(16)));
        const right = (below[2 * index + 1] ??= hexlify(randomBytes(16)));
        nodes.push(xmssHash(this.seed, xmssAdrs(XMSS_TYPE.TREE, index, level), left, right));
        if (sparse) break; // only the left-most branch is needed
      }
      this.levels.push(nodes);
    }
  }

  get root() {
    return this.levels[this.height][0];
  }

  // ERC-7913 key: seed || root
  get publicKey() {
    return this.seed + this.root.slice(2);
  }

  get nextLeaf() {
    return this.#nextLeaf;
  }

  #secret(leaf, chain) {
    return xmssHash(this.#skSeed, this.seed, xmssAdrs(XMSS_TYPE.WOTS_SK, leaf, chain));
  }

  #chain(x, leaf, chain, start, steps) {
    for (let j = start; j < start + steps; ++j)
      x = xmssHash(this.seed, xmssAdrs(XMSS_TYPE.WOTS_HASH, leaf, chain, j), x);
    return x;
  }

  #wotsPublicKey(leaf) {
    const ends = Array.from({ length: XMSS_LEN }, (_, i) => this.#chain(this.#secret(leaf, i), leaf, i, 0, XMSS_W - 1));
    return xmssHash(this.seed, xmssAdrs(XMSS_TYPE.WOTS_PK, leaf), ...ends);
  }

  // Signs with an explicit leaf. Reusing a leaf for a different digest breaks the scheme; tests use it on purpose.
  signWithLeaf(digest, leaf, randomizer = hexlify(randomBytes(16))) {
    assertArgument(dataLength(digest) === 32, 'invalid digest length', 'digest', digest);

    const messageDigest = xmssHash(this.seed, xmssAdrs(XMSS_TYPE.MESSAGE, leaf), this.root, randomizer, digest);
    const chains = xmssDigits(messageDigest).map((digit, i) => this.#chain(this.#secret(leaf, i), leaf, i, 0, digit));
    const path = Array.from({ length: this.height }, (_, level) => this.levels[level][(leaf >> level) ^ 1]);

    return {
      serialized: solidityPacked(
        ['uint32', 'bytes16', ...chains.map(() => 'bytes16'), ...path.map(() => 'bytes16')],
        [leaf, randomizer, ...chains, ...path],
      ),
    };
  }

  // Reserves the next leaf before signing, as a stateful signer must.
  sign(digest) {
    assertArgument(this.#nextLeaf < this.capacity, 'XMSS key exhausted', 'digest', digest);
    return this.signWithLeaf(digest, this.#nextLeaf++);
  }
}

module.exports = {
  ZKEmailSigningKey,
  XMSSSigningKey,
};
