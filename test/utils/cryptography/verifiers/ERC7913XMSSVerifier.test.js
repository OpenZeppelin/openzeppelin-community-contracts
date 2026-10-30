const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { XMSSSigningKey } = require('../../../helpers/signers');

const HEIGHT = 4;
const MAGIC_VALUE = ethers.id('verify(bytes,bytes32,bytes)').slice(0, 10); // IERC7913SignatureVerifier.verify.selector
const INVALID = '0xffffffff';

// Prepare keys in advance
const key = new XMSSSigningKey(HEIGHT);
const otherKey = new XMSSSigningKey(HEIGHT);

// Flips the byte at `offset` of a hex-encoded value
const flipByte = (data, offset) => {
  const bytes = ethers.getBytes(data);
  bytes[offset] ^= 0xff;
  return ethers.hexlify(bytes);
};

async function fixture() {
  const xmss = await ethers.deployContract('$XMSS');
  const verifier = await ethers.deployContract('$ERC7913XMSSVerifier', [HEIGHT]);
  return { xmss, verifier };
}

describe('ERC7913XMSSVerifier', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
    this.hash = ethers.hexlify(ethers.randomBytes(32));
  });

  it('reports the height', async function () {
    await expect(this.verifier.height()).to.eventually.equal(HEIGHT);
  });

  it('reverts on deployment with a height above the maximum', async function () {
    const factory = await ethers.getContractFactory('$ERC7913XMSSVerifier');
    await expect(ethers.deployContract('$ERC7913XMSSVerifier', [33]))
      .to.be.revertedWithCustomError(factory, 'ERC7913XMSSVerifierInvalidHeight')
      .withArgs(33);
  });

  it('computes the signature length', async function () {
    const { serialized } = key.signWithLeaf(this.hash, 0);
    await expect(this.xmss.$signatureLength(HEIGHT)).to.eventually.equal(ethers.dataLength(serialized));
  });

  it('computes the message digest', async function () {
    const leaf = 3;
    const randomizer = ethers.hexlify(ethers.randomBytes(16));
    const adrs = ethers.toBeHex((3n << 248n) | (BigInt(leaf) << 128n), 32); // ADRS(MESSAGE, leaf)
    const expected = ethers.dataSlice(
      ethers.keccak256(ethers.concat([key.seed, adrs, key.root, randomizer, this.hash])),
      0,
      16,
    );
    await expect(this.xmss.$messageDigest(key.seed, key.root, leaf, randomizer, this.hash)).to.eventually.equal(
      expected,
    );
  });

  describe('valid signatures', function () {
    it('accepts a signature from every leaf', async function () {
      for (let leaf = 0; leaf < 2 ** HEIGHT; ++leaf) {
        const { serialized } = key.signWithLeaf(this.hash, leaf);
        await expect(this.verifier.verify(key.publicKey, this.hash, serialized)).to.eventually.equal(MAGIC_VALUE);
      }
    });

    it('accepts a tree of height 0 (single one-time key)', async function () {
      const single = new XMSSSigningKey(0);
      const verifier = await ethers.deployContract('$ERC7913XMSSVerifier', [0]);
      const { serialized } = single.signWithLeaf(this.hash, 0);
      await expect(verifier.verify(single.publicKey, this.hash, serialized)).to.eventually.equal(MAGIC_VALUE);
    });

    for (const height of [16, 32]) {
      it(`accepts a tree of height ${height}`, async function () {
        const large = new XMSSSigningKey(height, { sparse: true });
        const verifier = await ethers.deployContract('$ERC7913XMSSVerifier', [height]);
        const { serialized } = large.sign(this.hash);
        await expect(verifier.verify(large.publicKey, this.hash, serialized)).to.eventually.equal(MAGIC_VALUE);
      });
    }
  });

  describe('invalid signatures', function () {
    beforeEach(function () {
      this.leaf = 5;
      this.signature = key.signWithLeaf(this.hash, this.leaf).serialized;
    });

    it('rejects a different hash', async function () {
      const other = ethers.hexlify(ethers.randomBytes(32));
      await expect(this.verifier.verify(key.publicKey, other, this.signature)).to.eventually.equal(INVALID);
    });

    it('rejects a different key', async function () {
      await expect(this.verifier.verify(otherKey.publicKey, this.hash, this.signature)).to.eventually.equal(INVALID);
    });

    it('rejects a key with the right root and a different seed', async function () {
      const publicKey = ethers.concat([otherKey.seed, key.root]);
      await expect(this.verifier.verify(publicKey, this.hash, this.signature)).to.eventually.equal(INVALID);
    });

    for (const length of [0, 31, 33, 64]) {
      it(`rejects a key of length ${length}`, async function () {
        const publicKey = ethers.dataSlice(ethers.concat([key.publicKey, key.publicKey]), 0, length);
        await expect(this.verifier.verify(publicKey, this.hash, this.signature)).to.eventually.equal(INVALID);
      });
    }

    it('rejects a different leaf index', async function () {
      const signature = ethers.concat([ethers.toBeHex(this.leaf ^ 1, 4), ethers.dataSlice(this.signature, 4)]);
      await expect(this.verifier.verify(key.publicKey, this.hash, signature)).to.eventually.equal(INVALID);
    });

    for (const [name, offset] of Object.entries({
      randomizer: 4,
      'first chain value': 20,
      'last chain value': 20 + 34 * 16,
      'first authentication path node': 580,
      'last authentication path node': 580 + (HEIGHT - 1) * 16,
    })) {
      it(`rejects a modified ${name}`, async function () {
        const signature = flipByte(this.signature, offset);
        await expect(this.verifier.verify(key.publicKey, this.hash, signature)).to.eventually.equal(INVALID);
      });
    }

    it('rejects a leaf index outside the tree', async function () {
      const signature = ethers.concat([
        ethers.toBeHex(this.leaf + 2 ** HEIGHT, 4),
        ethers.dataSlice(this.signature, 4),
      ]);
      await expect(this.verifier.verify(key.publicKey, this.hash, signature)).to.eventually.equal(INVALID);
    });

    it('rejects a signature with a shorter or longer authentication path', async function () {
      const shorter = ethers.dataSlice(this.signature, 0, ethers.dataLength(this.signature) - 16);
      const longer = ethers.concat([this.signature, ethers.randomBytes(16)]);
      await expect(this.verifier.verify(key.publicKey, this.hash, shorter)).to.eventually.equal(INVALID);
      await expect(this.verifier.verify(key.publicKey, this.hash, longer)).to.eventually.equal(INVALID);
    });

    it('rejects an empty signature', async function () {
      await expect(this.verifier.verify(key.publicKey, this.hash, '0x')).to.eventually.equal(INVALID);
    });
  });
});
