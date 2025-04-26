const { ethers, entrypoint } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { getDomain } = require('@openzeppelin/contracts/test/helpers/eip712');
const { ERC4337Helper } = require('../../helpers/erc4337');
const { PackedUserOperation } = require('../../helpers/eip712-types');
const { NonNativeSigner, P256SigningKey, RSASHA256SigningKey } = require('../../helpers/signers');

const { shouldBehaveLikeAccountCore } = require('../Account.behavior');
const { shouldBehaveLikeAccountERC7579 } = require('./AccountERC7579.behavior');
const { shouldBehaveLikeERC1271 } = require('../../utils/cryptography/ERC1271.behavior');

// Prepare signers in advance (RSA are long to initialize)
const signerECDSA = ethers.Wallet.createRandom();
const signerP256 = new NonNativeSigner(P256SigningKey.random());
const signerRSA = new NonNativeSigner(RSASHA256SigningKey.random());

async function fixture() {
  // EOAs and environment
  const [other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');
  const anotherTarget = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-7579 signature validator
  const signatureValidator = await ethers.deployContract('$ERC7579SignatureValidator');

  // ERC-7913 verifiers
  const verifierP256 = await ethers.deployContract('ERC7913SignatureVerifierP256');
  const verifierRSA = await ethers.deployContract('ERC7913SignatureVerifierRSA');

  // ERC-4337 env
  const helper = new ERC4337Helper();
  await helper.wait();
  const entrypointDomain = await getDomain(entrypoint.v08);
  const domain = {
    name: 'AccountERC7579',
    version: '1',
    chainId: entrypointDomain.chainId,
    verifyingContract: signatureValidator.target,
  };

  const signUserOp = function (userOp) {
    return this.signer
      .signTypedData(entrypointDomain, { PackedUserOperation }, userOp.packed)
      .then(signature => Object.assign(userOp, { signature: ethers.concat([signatureValidator.target, signature]) }));
  };

  const makeAccount = function (signer) {
    return this.helper.newAccount('$AccountERC7579Mock', [this.signatureValidator, signer]);
  };

  return {
    helper,
    signatureValidator,
    verifierP256,
    verifierRSA,
    domain,
    target,
    anotherTarget,
    other,
    signUserOp,
    makeAccount,
  };
}

describe('AccountERC7579', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  // Using ECDSA key as verifier
  describe('ECDSA key', function () {
    beforeEach(async function () {
      this.signer = signerECDSA;
      this.mock = await this.makeAccount(ethers.solidityPacked(['address'], [this.signer.address]));
    });

    shouldBehaveLikeAccountCore();
    shouldBehaveLikeAccountERC7579();
    shouldBehaveLikeERC1271();
  });

  // Using P256 key with an ERC-7913 verifier
  describe('P256 key', function () {
    beforeEach(async function () {
      this.signer = signerP256;
      this.mock = await this.helper.newAccount('$AccountERC7579Mock', [
        this.signatureValidator,
        ethers.concat([
          this.verifierP256.target,
          this.signer.signingKey.publicKey.qx,
          this.signer.signingKey.publicKey.qy,
        ]),
      ]);
    });

    shouldBehaveLikeAccountCore();
    shouldBehaveLikeAccountERC7579();
    shouldBehaveLikeERC1271();
  });

  // Using RSA key with an ERC-7913 verifier
  describe('RSA key', function () {
    beforeEach(async function () {
      this.signer = signerRSA;
      this.mock = await this.helper.newAccount('$AccountERC7579Mock', [
        this.signatureValidator,
        ethers.concat([
          this.verifierRSA.target,
          ethers.AbiCoder.defaultAbiCoder().encode(
            ['bytes', 'bytes'],
            [this.signer.signingKey.publicKey.e, this.signer.signingKey.publicKey.n],
          ),
        ]),
      ]);
    });

    shouldBehaveLikeAccountCore();
    shouldBehaveLikeAccountERC7579();
    shouldBehaveLikeERC1271();
  });
});
