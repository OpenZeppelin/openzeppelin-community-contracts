const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const ERC7786Attributes = require('../../helpers/erc7786attributes');

async function fixture() {
  const mock = await ethers.deployContract('$ERC7786Attributes');
  return { mock };
}

describe('ERC7786Attributes', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('requestRelay', function () {
    it('decode properly formatted attribute', async function () {
      const value = ethers.toBigInt(ethers.randomBytes(32));
      const gasLimit = ethers.toBigInt(ethers.randomBytes(32));
      const refundRecipient = ethers.getAddress(ethers.hexlify(ethers.randomBytes(20)));

      this.input = ERC7786Attributes.encodeFunctionData('requestRelay', [value, gasLimit, refundRecipient]);
      this.output = [true, value, gasLimit, refundRecipient];
    });

    it('data is too short', async function () {
      const value = ethers.toBigInt(ethers.randomBytes(32));
      const gasLimit = ethers.toBigInt(ethers.randomBytes(32));
      const refundRecipient = ethers.getAddress(ethers.hexlify(ethers.randomBytes(20)));

      this.input = ERC7786Attributes.encodeFunctionData('requestRelay', [value, gasLimit, refundRecipient]).slice(
        0,
        -2,
      ); // drop one byte
      this.output = [false, 0n, 0n, ethers.ZeroAddress];
    });

    it('wrong selector', async function () {
      this.input = ethers.hexlify(ethers.randomBytes(0x64));
      this.output = [false, 0n, 0n, ethers.ZeroAddress];
    });

    afterEach(async function () {
      await expect(this.mock.$tryDecodeRequestRelay(this.input)).to.eventually.deep.equal(this.output);
    });
  });
});
