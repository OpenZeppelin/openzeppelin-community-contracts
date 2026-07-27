const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { LibZip } = require('solady/js/solady');

const unittests = require('./testsuite');

async function fixture() {
  const mock = await ethers.deployContract('$FastLZ');
  return { mock };
}

describe('FastLZ', function () {
  before(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('decompress', function () {
    for (const { name, input } of unittests) {
      it(name, async function () {
        const raw = ethers.isBytesLike(input) ? input : ethers.toUtf8Bytes(input);
        const hex = ethers.hexlify(raw);
        const compressed = LibZip.flzCompress(hex);
        await expect(this.mock.$decompress(compressed)).to.eventually.equal(hex);
        await expect(this.mock.$decompressCalldata(compressed)).to.eventually.equal(hex);
      });
    }
  });
});
