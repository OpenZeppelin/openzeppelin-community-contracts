const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { getDomain } = require('@openzeppelin/contracts/test/helpers/eip712');
const { ERC4337Helper } = require('../helpers/erc4337');
const { NonNativeSigner, P256SigningKey, RSASHA256SigningKey, MultiERC7913SigningKey } = require('../helpers/signers');

const { shouldBehaveLikeAccountCore, shouldBehaveLikeAccountHolder } = require('./Account.behavior');
const { shouldBehaveLikeERC1271 } = require('../utils/cryptography/ERC1271.behavior');
const { shouldBehaveLikeERC7821 } = require('./extensions/ERC7821.behavior');
const { PackedUserOperation } = require('../helpers/eip712-types');

// Prepare signers in advance (RSA are long to initialize)
const signerECDSA1 = ethers.Wallet.createRandom();
const signerECDSA2 = ethers.Wallet.createRandom();
const signerECDSA3 = ethers.Wallet.createRandom();
const signerP256 = new NonNativeSigner(P256SigningKey.random());
const signerRSA = new NonNativeSigner(RSASHA256SigningKey.random());

// Minimal fixture common to the different signer verifiers
async function fixture() {
  // EOAs and environment
  const [beneficiary, other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-7913 verifiers
  const verifierP256 = await ethers.deployContract('ERC7913SignatureVerifierP256');
  const verifierRSA = await ethers.deployContract('ERC7913SignatureVerifierRSA');

  // ERC-4337 env
  const helper = new ERC4337Helper();
  await helper.wait();
  const entrypointDomain = await getDomain(entrypoint.v08);
  const domain = { name: 'AccountMultiERC7913', version: '1', chainId: entrypointDomain.chainId }; // Missing verifyingContract

  const makeMock = (signers, threshold) =>
    helper.newAccount('$AccountMultiERC7913Mock', ['AccountMultiERC7913', '1', signers, threshold]).then(mock => {
      domain.verifyingContract = mock.address;
      return mock;
    });

  // Sign user operations using MultiERC7913SigningKey
  const signUserOp = function (userOp) {
    return this.signer
      .signTypedData(entrypointDomain, { PackedUserOperation }, userOp.packed)
      .then(signature => Object.assign(userOp, { signature }));
  };

  const invalidSig = function () {
    return this.signer.signMessage('invalid');
  };

  return {
    helper,
    verifierP256,
    verifierRSA,
    domain,
    target,
    beneficiary,
    other,
    makeMock,
    signUserOp,
    invalidSig,
  };
}

describe('AccountMultiERC7913', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('Multi ECDSA signers with threshold=1', function () {
    beforeEach(async function () {
      this.signer = new NonNativeSigner(new MultiERC7913SigningKey([signerECDSA1]));
      this.mock = await this.makeMock([signerECDSA1.address], 1);
    });

    shouldBehaveLikeAccountCore();
    shouldBehaveLikeAccountHolder();
    shouldBehaveLikeERC1271({ erc7739: true });
    shouldBehaveLikeERC7821();
  });

  describe('Multi ECDSA signers with threshold=2', function () {
    beforeEach(async function () {
      this.signer = new NonNativeSigner(new MultiERC7913SigningKey([signerECDSA1, signerECDSA2]));
      this.mock = await this.makeMock([signerECDSA1.address, signerECDSA2.address], 2);
    });

    shouldBehaveLikeAccountCore();
    shouldBehaveLikeAccountHolder();
    shouldBehaveLikeERC1271({ erc7739: true });
    shouldBehaveLikeERC7821();
  });

  describe('Mixed signers with threshold=2', function () {
    beforeEach(async function () {
      // Create signers array with all three types
      signerP256.bytes = ethers.concat([
        this.verifierP256.target,
        signerP256.signingKey.publicKey.qx,
        signerP256.signingKey.publicKey.qy,
      ]);

      signerRSA.bytes = ethers.concat([
        this.verifierRSA.target,
        ethers.AbiCoder.defaultAbiCoder().encode(
          ['bytes', 'bytes'],
          [signerRSA.signingKey.publicKey.e, signerRSA.signingKey.publicKey.n],
        ),
      ]);

      this.signer = new NonNativeSigner(new MultiERC7913SigningKey([signerECDSA1, signerP256, signerRSA]));
      this.mock = await this.makeMock([signerECDSA1.address, signerP256.bytes, signerRSA.bytes], 2);
    });

    shouldBehaveLikeAccountCore();
    shouldBehaveLikeAccountHolder();
    shouldBehaveLikeERC1271({ erc7739: true });
    shouldBehaveLikeERC7821();
  });

  describe('Signer management', function () {
    const encodeECDSASigner = address => ethers.AbiCoder.defaultAbiCoder().encode(['bytes'], [address]);

    beforeEach(async function () {
      this.signer = new NonNativeSigner(new MultiERC7913SigningKey([signerECDSA1, signerECDSA2]));
      this.mock = await this.makeMock(
        [encodeECDSASigner(signerECDSA1.address), encodeECDSASigner(signerECDSA2.address)],
        1,
      );
      await this.mock.deploy();
    });

    it('can add signers', async function () {
      const signers = [
        encodeECDSASigner(signerECDSA3.address), // ECDSA Signer
      ];

      // Successfully adds a signer
      await expect(this.mock.$_addSigners(signers))
        .to.emit(this.mock, 'ERC7913SignersAdded')
        .withArgs(...signers);

      // Reverts if the signer was already added
      await expect(this.mock.$_addSigners(signers))
        .to.be.revertedWithCustomError(this.mock, 'MultiERC7913SignerAlreadyExists')
        .withArgs(...signers);
    });

    it('can remove signers', async function () {
      const signers = [encodeECDSASigner(signerECDSA2.address)];

      // Successfully removes an already added signer
      await expect(this.mock.$_removeSigners(signers))
        .to.emit(this.mock, 'ERC7913SignersRemoved')
        .withArgs(...signers);

      // Reverts removing a signer if it doesn't exist
      await expect(this.mock.$_removeSigners(signers))
        .to.be.revertedWithCustomError(this.mock, 'MultiERC7913SignerNonexistentSigner')
        .withArgs(...signers);
    });

    it('can change threshold', async function () {
      // Reachable threshold is set
      await expect(this.mock.$_setThreshold(2)).to.emit(this.mock, 'ThresholdSet');

      // Unreachable threshold reverts
      await expect(this.mock.$_setThreshold(3)).to.revertedWithCustomError(
        this.mock,
        'MultiERC7913UnreachableThreshold',
      );
    });
  });
});
