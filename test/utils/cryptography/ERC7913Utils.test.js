const { expect } = require('chai');
const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const TEST_MESSAGE = ethers.id('OpenZeppelin');
const TEST_MESSAGE_HASH = ethers.hashMessage(TEST_MESSAGE);

const WRONG_MESSAGE = ethers.id('Nope');
const WRONG_MESSAGE_HASH = ethers.hashMessage(WRONG_MESSAGE);

async function fixture() {
  const [, signer, other] = await ethers.getSigners();
  const mock = await ethers.deployContract('$ERC7913Utils');

  // Deploy a mock ERC-1271 wallet
  const wallet = await ethers.deployContract('ERC1271WalletMock', [signer]);

  // Deploy a mock ERC-7913 verifier
  const verifier = await ethers.deployContract('ERC7913VerifierMock');

  // Create test keys
  const validKey = ethers.toUtf8Bytes('valid_key');
  const invalidKey = ethers.randomBytes(32);

  // Create signer bytes (verifier address + key)
  const validSignerBytes = ethers.concat([verifier.target, validKey]);
  const invalidKeySignerBytes = ethers.concat([verifier.target, invalidKey]);

  // Create test signatures
  const validSignature = ethers.toUtf8Bytes('valid_signature');
  const invalidSignature = ethers.randomBytes(65);

  // Get EOA signature from the signer
  const eoaSignature = await signer.signMessage(TEST_MESSAGE);

  return {
    signer,
    other,
    mock,
    wallet,
    verifier,
    validKey,
    invalidKey,
    validSignerBytes,
    invalidKeySignerBytes,
    validSignature,
    invalidSignature,
    eoaSignature,
  };
}

describe('ERC7913Utils', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('isValidSignatureNow', function () {
    describe('with EOA signer', function () {
      it('with matching signer and signature', async function () {
        const eoaSigner = ethers.zeroPadValue(this.signer.address, 20);
        await expect(this.mock.$isValidSignatureNow(eoaSigner, TEST_MESSAGE_HASH, this.eoaSignature)).to.eventually.be
          .true;
      });

      it('with invalid signer', async function () {
        const eoaSigner = ethers.zeroPadValue(this.other.address, 20);
        await expect(this.mock.$isValidSignatureNow(eoaSigner, TEST_MESSAGE_HASH, this.eoaSignature)).to.eventually.be
          .false;
      });

      it('with invalid signature', async function () {
        const eoaSigner = ethers.zeroPadValue(this.signer.address, 20);
        await expect(this.mock.$isValidSignatureNow(eoaSigner, WRONG_MESSAGE_HASH, this.eoaSignature)).to.eventually.be
          .false;
      });
    });

    describe('with ERC-1271 wallet', function () {
      it('with matching signer and signature', async function () {
        const walletSigner = ethers.zeroPadValue(this.wallet.target, 20);
        await expect(this.mock.$isValidSignatureNow(walletSigner, TEST_MESSAGE_HASH, this.eoaSignature)).to.eventually
          .be.true;
      });

      it('with invalid signer', async function () {
        const walletSigner = ethers.zeroPadValue(this.mock.target, 20);
        await expect(this.mock.$isValidSignatureNow(walletSigner, TEST_MESSAGE_HASH, this.eoaSignature)).to.eventually
          .be.false;
      });

      it('with invalid signature', async function () {
        const walletSigner = ethers.zeroPadValue(this.wallet.target, 20);
        await expect(this.mock.$isValidSignatureNow(walletSigner, WRONG_MESSAGE_HASH, this.eoaSignature)).to.eventually
          .be.false;
      });
    });

    describe('with ERC-7913 verifier', function () {
      it('with matching signer and signature', async function () {
        await expect(this.mock.$isValidSignatureNow(this.validSignerBytes, TEST_MESSAGE_HASH, this.validSignature)).to
          .eventually.be.true;
      });

      it('with invalid verifier', async function () {
        const invalidVerifierSigner = ethers.concat([this.mock.target, this.validKey]);
        await expect(this.mock.$isValidSignatureNow(invalidVerifierSigner, TEST_MESSAGE_HASH, this.validSignature)).to
          .eventually.be.false;
      });

      it('with invalid key', async function () {
        await expect(this.mock.$isValidSignatureNow(this.invalidKeySignerBytes, TEST_MESSAGE_HASH, this.validSignature))
          .to.eventually.be.false;
      });

      it('with invalid signature', async function () {
        await expect(this.mock.$isValidSignatureNow(this.validSignerBytes, TEST_MESSAGE_HASH, this.invalidSignature)).to
          .eventually.be.false;
      });

      it('with signer too short', async function () {
        const shortSigner = ethers.randomBytes(19);
        await expect(this.mock.$isValidSignatureNow(shortSigner, TEST_MESSAGE_HASH, this.validSignature)).to.eventually
          .be.false;
      });
    });
  });
});
