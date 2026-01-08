const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { min } = require('@openzeppelin/contracts/test/helpers/math');

const lz4js = require('lz4js');
const snappy = require('snappy');
const { LibZip } = require('solady/js/solady');

const unittests = require('./testsuite');

async function fixture() {
  const fastlz = await ethers.deployContract('$FastLZ');
  const lz4 = await ethers.deployContract('$LZ4');
  const snappy = await ethers.deployContract('$Snappy');
  return { fastlz, lz4, snappy };
}

describe('Gas comparison of decompression algorithms', function () {
  before(async function () {
    Object.assign(this, await loadFixture(fixture));
    this.results = [];
  });

  describe('decompress', function () {
    for (const { name, input } of unittests) {
      it(name, async function () {
        const raw = ethers.isBytesLike(input) ? input : ethers.toUtf8Bytes(input);
        const hex = ethers.hexlify(raw);

        const compressedFastlz = LibZip.flzCompress(hex);
        const compressedSnappy = snappy.compressSync(raw);
        const compressedLz4 = lz4js.compress(raw);

        const gasUsedFastlz = await this.fastlz.$decompress.estimateGas(compressedFastlz).then(Number);
        const gasUsedSnappy = await this.snappy.$uncompress.estimateGas(compressedSnappy).then(Number);
        const gasUsedLz4 = await this.lz4.$decompress.estimateGas(compressedLz4).then(Number);
        const lowest = min(gasUsedFastlz, gasUsedSnappy, gasUsedLz4);

        this.results.push({
          name,
          lowest,
          extraGasUsedPercentageFastlz: `+${((100 * (gasUsedFastlz - lowest)) / lowest).toFixed(2)}%`,
          extraGasUsedPercentageSnappy: `+${((100 * (gasUsedSnappy - lowest)) / lowest).toFixed(2)}%`,
          extraGasUsedPercentageLz4: `+${((100 * (gasUsedLz4 - lowest)) / lowest).toFixed(2)}%`,
        });
      });
    }

    after(async function () {
      console.table(this.results);
    });
  });
});
