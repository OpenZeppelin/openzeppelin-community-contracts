const { ethers } = require('hardhat');
const { expect } = require('chai');
const { Permit, formatType, getDomain } = require('../../../lib/@openzeppelin-contracts/test/helpers/eip712');
const { PersonalSignHelper, TypedDataSignHelper } = require('../../helpers/erc7739');

function shouldBehaveLikeERC7739Signer() {
  const MAGIC_VALUE = '0x1626ba7e';

  describe('isValidSignature', function () {
    beforeEach(async function () {
      this.signTypedData ??= this.signer.signTypedData.bind(this.signer);
      this.domain ??= await getDomain(this.mock);
    });

    describe('PersonalSign', function () {
      it('returns true for a valid personal signature', async function () {
        const text = 'Hello, world!';

        const hash = PersonalSignHelper.hash(text);
        const signature = await PersonalSignHelper.sign(this.signTypedData, text, this.domain);

        expect(this.mock.isValidSignature(hash, signature)).to.eventually.equal(MAGIC_VALUE);
      });

      it('returns false for an invalid personal signature', async function () {
        const hash = PersonalSignHelper.hash('Message the app expects');
        const signature = await PersonalSignHelper.sign(this.signTypedData, 'Message signed is different', this.domain);

        expect(this.mock.isValidSignature(hash, signature)).to.eventually.not.equal(MAGIC_VALUE);
      });
    });

    describe('TypedDataSign', function () {
      beforeEach(async function () {
        // Dummy app domain, different from the ERC7739Signer's domain
        // Note the difference of format (signer domain doesn't include a salt, but app domain does)
        this.appDomain = {
          name: 'SomeApp',
          version: '1',
          chainId: this.domain.chainId,
          verifyingContract: '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512',
          salt: '0x02cb3d8cb5e8928c9c6de41e935e16a4e28b2d54e7e7ba47e99f16071efab785',
        };
      });

      it('returns true for a valid typed data signature', async function () {
        const contents = {
          owner: '0x1ab5E417d9AF00f1ca9d159007e12c401337a4bb',
          spender: '0xD68E96620804446c4B1faB3103A08C98d4A8F55f',
          value: 1_000_000n,
          nonce: 0n,
          deadline: ethers.MaxUint256,
        };
        const message = TypedDataSignHelper.prepare(contents, this.domain);

        const hash = ethers.TypedDataEncoder.hash(this.appDomain, { Permit }, message.contents);
        const signature = await TypedDataSignHelper.sign(this.signTypedData, this.appDomain, { Permit }, message);

        expect(this.mock.isValidSignature(hash, signature)).to.eventually.equal(MAGIC_VALUE);
      });

      it('returns true for valid typed data signature (nested types)', async function () {
        const contentsTypes = {
          B: formatType({ z: 'Z' }),
          Z: formatType({ a: 'A' }),
          A: formatType({ v: 'uint256' }),
        };

        const contents = { z: { a: { v: 1n } } };
        const message = TypedDataSignHelper.prepare(contents, this.domain);

        const hash = TypedDataSignHelper.hash(this.appDomain, contentsTypes, message.contents);
        const signature = await TypedDataSignHelper.sign(this.signTypedData, this.appDomain, contentsTypes, message);

        expect(this.mock.isValidSignature(hash, signature)).to.eventually.equal(MAGIC_VALUE);
      });

      it('returns false for an invalid typed data signature', async function () {
        const appContents = {
          owner: '0x1ab5E417d9AF00f1ca9d159007e12c401337a4bb',
          spender: '0xD68E96620804446c4B1faB3103A08C98d4A8F55f',
          value: 1_000_000n,
          nonce: 0n,
          deadline: ethers.MaxUint256,
        };
        // message signed by the user is for a lower amount.
        const message = TypedDataSignHelper.prepare({ ...appContents, value: 1_000n }, this.domain);

        const hash = ethers.TypedDataEncoder.hash(this.appDomain, { Permit }, appContents);
        const signature = await TypedDataSignHelper.sign(this.signTypedData, this.appDomain, { Permit }, message);

        expect(this.mock.isValidSignature(hash, signature)).to.eventually.not.equal(MAGIC_VALUE);
      });
    });

    it('support detection', function () {
      expect(
        this.mock.isValidSignature('0x7739773977397739773977397739773977397739773977397739773977397739', ''),
      ).to.eventually.equal('0x77390001');
    });
  });
}

module.exports = {
  shouldBehaveLikeERC7739Signer,
};
