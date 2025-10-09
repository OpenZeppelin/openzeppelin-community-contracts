const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const lz4js = require('lz4js');

const unittests = require('./testsuite');

async function fixture() {
  const mock = await ethers.deployContract('$LZ4');
  return { mock };
}

describe('LZ4', function () {
  before(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('decompress', function () {
    for (const { name, input } of unittests) {
      it(name, async function () {
        const raw = ethers.isBytesLike(input) ? input : ethers.toUtf8Bytes(input);
        const hex = ethers.hexlify(raw);
        const compressed = lz4js.compress(raw);
        await expect(this.mock.$decompress(compressed)).to.eventually.equal(hex);
        await expect(this.mock.$decompressCalldata(compressed)).to.eventually.equal(hex);
      });
    }
  });
});
