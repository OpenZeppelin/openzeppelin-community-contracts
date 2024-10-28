const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { getDomain, formatType, Permit } = require('../../helpers/eip712');
const { PersonalSignHelper, TypedDataSignHelper } = require('../../helpers/erc7739');

// Constant
const MAGIC_VALUE = '0x1626ba7e';

// Fixture
async function fixture() {
  const [signer] = await ethers.getSigners();
  const mock = await ethers.deployContract('$ERC7739SignerMock', [signer]);
  const domain = await getDomain(mock);

  return {
    mock,
    domain,
    signTypedData: signer.signTypedData.bind(signer),
  };
}

describe('ERC7739Signer', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('isValidSignature', function () {
    describe('PersonalSign', async function () {
      it('returns true for a valid personal signature', async function () {
        const text = 'Hello, world!';

        const hash = PersonalSignHelper.hash(text);
        const signature = await PersonalSignHelper.sign(this.signTypedData, text, this.domain);

        expect(await this.mock.isValidSignature(hash, signature)).to.equal(MAGIC_VALUE);
      });

      it('returns false for an invalid personal signature', async function () {
        const hash = PersonalSignHelper.hash('Message the app expects');
        const signature = await PersonalSignHelper.sign(this.signTypedData, 'Message signed is different', this.domain);

        expect(await this.mock.isValidSignature(hash, signature)).to.not.equal(MAGIC_VALUE);
      });
    });

    describe('TypedDataSign', async function () {
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
        const message = { contents, ...this.domain };

        const hash = ethers.TypedDataEncoder.hash(this.appDomain, { Permit }, message.contents);
        const signature = await TypedDataSignHelper.sign(this.signTypedData, this.appDomain, { Permit }, message);

        expect(await this.mock.isValidSignature(hash, signature)).to.equal(MAGIC_VALUE);
      });

      it('returns true for valid typed data signature (nested types)', async function () {
        const contentsTypes = {
          B: formatType({ z: 'Z' }),
          Z: formatType({ a: 'A' }),
          A: formatType({ v: 'uint256' }),
        };

        const contents = { z: { a: { v: 1n } } };
        const message = { contents, ...this.domain };

        const hash = TypedDataSignHelper.hash(this.appDomain, contentsTypes, message.contents);
        const signature = await TypedDataSignHelper.sign(this.signTypedData, this.appDomain, contentsTypes, message);

        expect(await this.mock.isValidSignature(hash, signature)).to.equal(MAGIC_VALUE);
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
        const message = { contents: { ...appContents, value: 1_000n }, ...this.domain };

        const hash = ethers.TypedDataEncoder.hash(this.appDomain, { Permit }, appContents);
        const signature = await TypedDataSignHelper.sign(this.signTypedData, this.appDomain, { Permit }, message);

        expect(await this.mock.isValidSignature(hash, signature)).to.not.equal(MAGIC_VALUE);
      });
    });
  });
});
