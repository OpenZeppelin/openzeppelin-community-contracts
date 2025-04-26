const { expect } = require('chai');
const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { PANIC_CODES } = require('@nomicfoundation/hardhat-chai-matchers/panic');

const TEST_MESSAGE = 'OpenZeppelin';
const TEST_MESSAGE_HASH = ethers.hashMessage(TEST_MESSAGE);

const WRONG_MESSAGE = 'Nope';
const WRONG_MESSAGE_HASH = ethers.hashMessage(WRONG_MESSAGE);

async function fixture() {
  const [, signer, other, extraSigner] = await ethers.getSigners();
  const mock = await ethers.deployContract('$ERC7913Utils');

  // Deploy a mock ERC-1271 wallet
  const wallet = await ethers.deployContract('ERC1271WalletMock', [signer]);
  const wallet2 = await ethers.deployContract('ERC1271WalletMock', [extraSigner]);

  // Deploy a mock ERC-7913 verifier
  const verifier = await ethers.deployContract('ERC7913VerifierMock');

  // Create test keys
  const validKey = ethers.toUtf8Bytes('valid_key_1');
  const validKey2 = ethers.toUtf8Bytes('valid_key_2');
  const invalidKey = ethers.randomBytes(32);

  // Create signer bytes (verifier address + key)
  const validSignerBytes = ethers.concat([verifier.target, validKey]);
  const validSignerBytes2 = ethers.concat([verifier.target, validKey2]);
  const invalidKeySignerBytes = ethers.concat([verifier.target, invalidKey]);

  // Create test signatures
  const validSignature = ethers.toUtf8Bytes('valid_signature_1');
  const validSignature2 = ethers.toUtf8Bytes('valid_signature_2');
  const invalidSignature = ethers.randomBytes(65);

  // Get EOA signatures from the signers
  const eoaSignature = await signer.signMessage(TEST_MESSAGE);
  const eoaSignature2 = await extraSigner.signMessage(TEST_MESSAGE);
  const wrongMessageSignature = await signer.signMessage(WRONG_MESSAGE);

  // Create EOA signers
  const eoaSigner = ethers.zeroPadValue(signer.address, 20);
  const eoaSigner2 = ethers.zeroPadValue(extraSigner.address, 20);
  const wrongSigner = ethers.zeroPadValue(other.address, 20);

  // Create Wallet signers
  const walletSigner = ethers.zeroPadValue(wallet.target, 20);
  const walletSigner2 = ethers.zeroPadValue(wallet2.target, 20);

  return {
    signer,
    other,
    extraSigner,
    mock,
    wallet,
    wallet2,
    verifier,
    validKey,
    validKey2,
    invalidKey,
    validSignerBytes,
    validSignerBytes2,
    invalidKeySignerBytes,
    validSignature,
    validSignature2,
    invalidSignature,
    eoaSignature,
    eoaSignature2,
    wrongMessageSignature,
    eoaSigner,
    eoaSigner2,
    wrongSigner,
    walletSigner,
    walletSigner2,
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

  describe('isValidNSignaturesNow', function () {
    it('should validate a single signature', async function () {
      await expect(this.mock.$isValidNSignaturesNow(TEST_MESSAGE_HASH, [this.eoaSigner], [this.eoaSignature])).to
        .eventually.be.true;
    });

    it('should validate multiple signatures with different signer types', async function () {
      // Order signers by ID (using keccak256)
      const signers = [this.eoaSigner, this.walletSigner, this.validSignerBytes].sort(
        (a, b) => ethers.keccak256(a) - ethers.keccak256(b),
      );

      // Create corresponding signatures in the same order
      const signatures = signers.map(signer => {
        if (ethers.dataLength(signer) === 20) {
          // EOA or ERC-1271 wallet
          if (ethers.getAddress(ethers.hexlify(signer)) === this.signer.address) {
            return this.eoaSignature;
          } else if (ethers.hexlify(signer) === ethers.hexlify(this.walletSigner)) {
            return this.eoaSignature; // wallet uses signer's signature
          }
        } else {
          // ERC-7913 verifier
          return this.validSignature;
        }
        return ethers.randomBytes(65); // fallback, shouldn't be reached
      });

      await expect(this.mock.$isValidNSignaturesNow(TEST_MESSAGE_HASH, signers, signatures)).to.eventually.be.true;
    });

    it('should validate multiple EOA signatures', async function () {
      // Sort by signer ID
      const signers = [this.eoaSigner, this.eoaSigner2].sort((a, b) => ethers.keccak256(a) - ethers.keccak256(b));

      // Map of signer to signature
      const signatureMap = {
        [ethers.hexlify(this.eoaSigner)]: this.eoaSignature,
        [ethers.hexlify(this.eoaSigner2)]: this.eoaSignature2,
      };

      const signatures = signers.map(signer => signatureMap[ethers.hexlify(signer)]);

      await expect(this.mock.$isValidNSignaturesNow(TEST_MESSAGE_HASH, signers, signatures)).to.eventually.be.true;
    });

    it('should validate multiple ERC-1271 wallet signatures', async function () {
      // Sort by signer ID
      const signers = [this.walletSigner, this.walletSigner2].sort((a, b) => ethers.keccak256(a) - ethers.keccak256(b));

      // Both wallets use their respective owner's signatures
      const signatures = [this.eoaSignature, this.eoaSignature2];
      if (ethers.keccak256(this.walletSigner) - ethers.keccak256(this.walletSigner2) > 0) {
        signatures.reverse();
      }

      await expect(this.mock.$isValidNSignaturesNow(TEST_MESSAGE_HASH, signers, signatures)).to.eventually.be.true;
    });

    it('should validate multiple ERC-7913 signatures', async function () {
      // Sort by signer ID
      const signers = [this.validSignerBytes, this.validSignerBytes2].sort(
        (a, b) => ethers.keccak256(a) - ethers.keccak256(b),
      );

      // Map of signer to signature
      const signatureMap = {
        [ethers.hexlify(this.validSignerBytes)]: this.validSignature,
        [ethers.hexlify(this.validSignerBytes2)]: this.validSignature2,
      };

      const signatures = signers.map(signer => signatureMap[ethers.hexlify(signer)]);

      await expect(this.mock.$isValidNSignaturesNow(TEST_MESSAGE_HASH, signers, signatures)).to.eventually.be.true;
    });

    it('should return false if any signature is invalid', async function () {
      // Use two EOA signers but one signature is for the wrong message
      await expect(
        this.mock.$isValidNSignaturesNow(
          TEST_MESSAGE_HASH,
          [this.eoaSigner, this.eoaSigner2],
          [this.eoaSignature, this.wrongMessageSignature],
        ),
      ).to.eventually.be.false;
    });

    it('should return false if signers are not ordered by ID', async function () {
      // Ensure signers are ordered incorrectly
      const signers = [this.eoaSigner, this.eoaSigner2];
      const signatures = [this.eoaSignature, this.eoaSignature2];

      // If they're already ordered, swap them
      if (ethers.keccak256(signers[0]) - ethers.keccak256(signers[1])) {
        signers.reverse();
        signatures.reverse();
      }

      await expect(this.mock.$isValidNSignaturesNow(TEST_MESSAGE_HASH, signers, signatures)).to.eventually.be.false;
    });

    it('should return false if there are duplicate signers', async function () {
      await expect(
        this.mock.$isValidNSignaturesNow(
          TEST_MESSAGE_HASH,
          [this.eoaSigner, this.eoaSigner], // Same signer used twice
          [this.eoaSignature, this.eoaSignature],
        ),
      ).to.eventually.be.false;
    });

    it('should fail if signatures array length does not match signers array length', async function () {
      await expect(
        this.mock.$isValidNSignaturesNow(
          TEST_MESSAGE_HASH,
          [this.eoaSigner, this.eoaSigner2],
          [this.eoaSignature], // Missing one signature
        ),
      ).to.be.revertedWithPanic(PANIC_CODES.ARRAY_ACCESS_OUT_OF_BOUNDS);
    });

    it('should pass with empty arrays', async function () {
      await expect(this.mock.$isValidNSignaturesNow(TEST_MESSAGE_HASH, [], [])).to.eventually.be.true;
    });
  });
});
