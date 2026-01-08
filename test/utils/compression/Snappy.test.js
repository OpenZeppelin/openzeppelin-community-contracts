const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const snappy = require('snappy');

const unittests = require('./testsuite');

async function fixture() {
  const mock = await ethers.deployContract('$Snappy');
  return { mock };
}

describe('Snappy', function () {
  before(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('uncompress', function () {
    for (const { name, input } of unittests) {
      it(name, async function () {
        const raw = ethers.isBytesLike(input) ? input : ethers.toUtf8Bytes(input);
        const hex = ethers.hexlify(raw);
        const compressed = snappy.compressSync(raw);
        await expect(this.mock.$uncompress(compressed)).to.eventually.equal(hex);
        await expect(this.mock.$uncompressCalldata(compressed)).to.eventually.equal(hex);
      });
    }
  });
});
