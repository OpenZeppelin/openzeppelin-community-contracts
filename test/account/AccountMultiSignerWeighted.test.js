const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { getDomain } = require('@openzeppelin/contracts/test/helpers/eip712');
const { ERC4337Helper } = require('../helpers/erc4337');
const { NonNativeSigner, P256SigningKey, RSASHA256SigningKey, MultiERC7913SigningKey } = require('../helpers/signers');
const { PackedUserOperation } = require('../helpers/eip712-types');

const { shouldBehaveLikeAccountCore, shouldBehaveLikeAccountHolder } = require('./Account.behavior');
const { shouldBehaveLikeERC1271 } = require('../utils/cryptography/ERC1271.behavior');
const { shouldBehaveLikeERC7821 } = require('./extensions/ERC7821.behavior');

// Prepare signers in advance (RSA are long to initialize)
const signerECDSA1 = ethers.Wallet.createRandom();
const signerECDSA2 = ethers.Wallet.createRandom();
const signerECDSA3 = ethers.Wallet.createRandom();
const signerECDSA4 = ethers.Wallet.createRandom();
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
  const domain = { name: 'AccountMultiSignerWeighted', version: '1', chainId: entrypointDomain.chainId }; // Missing verifyingContract

  const makeMock = (signers, weights, threshold) =>
    helper
      .newAccount('$AccountMultiSignerWeightedMock', ['AccountMultiSignerWeighted', '1', signers, weights, threshold])
      .then(mock => {
        domain.verifyingContract = mock.address;
        return mock;
      });

  // Sign user operations using NonNativeSigner with MultiERC7913SigningKey
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

describe('AccountMultiSignerWeighted', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('Weighted signers with equal weights (1, 1, 1) and threshold=2', function () {
    beforeEach(async function () {
      const weights = [1, 1, 1];
      this.signer = new NonNativeSigner(
        new MultiERC7913SigningKey([signerECDSA1, signerECDSA2, signerECDSA3], weights),
      );
      this.mock = await this.makeMock([signerECDSA1.address, signerECDSA2.address, signerECDSA3.address], weights, 2);
    });

    shouldBehaveLikeAccountCore();
    shouldBehaveLikeAccountHolder();
    shouldBehaveLikeERC1271({ erc7739: true });
    shouldBehaveLikeERC7821();
  });

  describe('Weighted signers with varying weights (1, 2, 3) and threshold=3', function () {
    beforeEach(async function () {
      const weights = [1, 2, 3];
      this.signer = new NonNativeSigner(new MultiERC7913SigningKey([signerECDSA1, signerECDSA2], weights.slice(1)));
      this.mock = await this.makeMock([signerECDSA1.address, signerECDSA2.address, signerECDSA3.address], weights, 3);
    });

    shouldBehaveLikeAccountCore();
    shouldBehaveLikeAccountHolder();
    shouldBehaveLikeERC1271({ erc7739: true });
    shouldBehaveLikeERC7821();
  });

  describe('Mixed weighted signers with threshold=4', function () {
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

      const weights = [1, 2, 3];
      this.signer = new NonNativeSigner(new MultiERC7913SigningKey([signerECDSA1, signerP256, signerRSA], weights));
      this.mock = await this.makeMock(
        [signerECDSA1.address, signerP256.bytes, signerRSA.bytes],
        weights,
        4, // Requires at least signer2 + signer3, or all three signers
      );
    });

    shouldBehaveLikeAccountCore();
    shouldBehaveLikeAccountHolder();
    shouldBehaveLikeERC1271({ erc7739: true });
    shouldBehaveLikeERC7821();
  });

  describe('Weight management', function () {
    beforeEach(async function () {
      const weights = [1, 2, 3];
      this.signer = new NonNativeSigner(
        new MultiERC7913SigningKey([signerECDSA1, signerECDSA2, signerECDSA3], weights),
      );
      this.mock = await this.makeMock([signerECDSA1.address, signerECDSA2.address, signerECDSA3.address], weights, 4);
      await this.mock.deploy();
    });

    it('verifies signerId function returns keccak256(signer)', async function () {
      const signer = signerECDSA1.address;
      await expect(this.mock.signerId(signer)).to.eventually.equal(ethers.keccak256(signer));
    });

    it('can get signer weights', async function () {
      const signer1 = signerECDSA1.address;
      const signer2 = signerECDSA2.address;
      const signer3 = signerECDSA3.address;

      await expect(this.mock.signerWeight(signer1)).to.eventually.equal(1);
      await expect(this.mock.signerWeight(signer2)).to.eventually.equal(2);
      await expect(this.mock.signerWeight(signer3)).to.eventually.equal(3);
    });

    it('can update signer weights', async function () {
      const signer1 = signerECDSA1.address;
      const signer2 = signerECDSA2.address;
      const signer3 = signerECDSA3.address;

      // Successfully updates weights and emits event
      await expect(this.mock.$_setSignerWeights([signer1, signer2], [5, 5]))
        .to.emit(this.mock, 'ERC7913SignerWeightChanged')
        .withArgs(signer1, 5)
        .to.emit(this.mock, 'ERC7913SignerWeightChanged')
        .withArgs(signer2, 5);

      await expect(this.mock.signerWeight(signer1)).to.eventually.equal(5);
      await expect(this.mock.signerWeight(signer2)).to.eventually.equal(5);
      await expect(this.mock.signerWeight(signer3)).to.eventually.equal(3); // unchanged
    });

    it('cannot set weight to non-existent signer', async function () {
      const randomSigner = ethers.Wallet.createRandom().address;

      // Reverts when setting weight for non-existent signer
      await expect(this.mock.$_setSignerWeights([randomSigner], [1]))
        .to.be.revertedWithCustomError(this.mock, 'MultiSignerERC7913NonexistentSigner')
        .withArgs(randomSigner.toLowerCase());
    });

    it('cannot set weight to 0', async function () {
      const signer1 = signerECDSA1.address;

      // Reverts when setting weight to 0
      await expect(this.mock.$_setSignerWeights([signer1], [0]))
        .to.be.revertedWithCustomError(this.mock, 'MultiERC7913WeightedInvalidWeight')
        .withArgs(signer1.toLowerCase(), 0);
    });

    it('requires signers and weights arrays to have same length', async function () {
      const signer1 = signerECDSA1.address;
      const signer2 = signerECDSA2.address;

      // Reverts when arrays have different lengths
      await expect(this.mock.$_setSignerWeights([signer1, signer2], [1])).to.be.revertedWithCustomError(
        this.mock,
        'MultiERC7913WeightedMismatchedLength',
      );
    });

    it('validates threshold is reachable when updating weights', async function () {
      const signer1 = signerECDSA1.address;
      const signer2 = signerECDSA2.address;
      const signer3 = signerECDSA3.address;

      // First, lower the weights so the sum is exactly 6 (just enough for threshold=6)
      await expect(this.mock.$_setSignerWeights([signer1, signer2, signer3], [1, 2, 3])).to.emit(
        this.mock,
        'ERC7913SignerWeightChanged',
      );

      // Increase threshold to 6
      await expect(this.mock.$_setThreshold(6)).to.emit(this.mock, 'ThresholdSet').withArgs(6);

      // Now try to lower weights so their sum is less than the threshold
      await expect(this.mock.$_setSignerWeights([signer1, signer2, signer3], [1, 1, 1])).to.be.revertedWithCustomError(
        this.mock,
        'MultiERC7913UnreachableThreshold',
      );
    });

    it('reports default weight of 1 for signers without explicit weight', async function () {
      const signer4 = signerECDSA4.address;

      // Add a new signer without setting weight
      await this.mock.$_addSigners([signer4]);

      // Should have default weight of 1
      await expect(this.mock.signerWeight(signer4)).to.eventually.equal(1);
    });

    it('can get total weight of all signers', async function () {
      await expect(this.mock.totalWeight()).to.eventually.equal(6); // 1 + 2 + 3
    });

    it('updates total weight when adding and removing signers', async function () {
      const signer4 = signerECDSA4.address;

      // Add a new signer - should increase total weight by default weight (1)
      await this.mock.$_addSigners([signer4]);
      await expect(this.mock.totalWeight()).to.eventually.equal(7); // 6 + 1

      // Set weight to 5 - should increase total weight by 4
      await this.mock.$_setSignerWeights([signer4], [5]);
      await expect(this.mock.totalWeight()).to.eventually.equal(11); // 7 + 4

      // Remove signer - should decrease total weight by current weight (5)
      await this.mock.$_removeSigners([signer4]);
      await expect(this.mock.totalWeight()).to.eventually.equal(6); // 11 - 5
    });
  });
});
