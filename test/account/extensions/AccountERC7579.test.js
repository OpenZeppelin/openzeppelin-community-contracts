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
  const erc7579Validator = await ethers.deployContract('$ERC7579Signature');

  // ERC-7913 verifiers
  const verifierP256 = await ethers.deployContract('ERC7913P256Verifier');
  const verifierRSA = await ethers.deployContract('ERC7913RSAVerifier');

  // ERC-4337 env
  const helper = new ERC4337Helper();
  await helper.wait();
  const entrypointDomain = await getDomain(entrypoint.v08);
  const domain = {
    name: 'AccountERC7579',
    version: '1',
    chainId: entrypointDomain.chainId,
    verifyingContract: erc7579Validator.target,
  };

  const makeAccount = function (signer) {
    return this.helper.newAccount('$AccountERC7579Mock', [this.erc7579Validator, signer]);
  };

  return {
    helper,
    erc7579Validator,
    verifierP256,
    verifierRSA,
    entrypointDomain,
    domain,
    target,
    anotherTarget,
    other,
    makeAccount,
    userOp: {
      nonce: ethers.zeroPadBytes(ethers.hexlify(erc7579Validator.target), 32),
    },
  };
}

function prepareSigner(prototype) {
  this.signer.signMessage = message =>
    prototype.signMessage.call(this.signer, message).then(sign => ethers.concat([this.erc7579Validator.target, sign]));
  this.signer.signTypedData = (domain, types, values) =>
    prototype.signTypedData
      .call(this.signer, domain, types, values)
      .then(sign => ethers.concat([this.erc7579Validator.target, sign]));
  this.signUserOp = userOp =>
    prototype.signTypedData
      .call(this.signer, this.entrypointDomain, { PackedUserOperation }, userOp.packed)
      .then(signature => Object.assign(userOp, { signature }));
}

describe('AccountERC7579', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  // Using ECDSA key as verifier
  describe('ECDSA key', function () {
    beforeEach(async function () {
      this.signer = signerECDSA;
      prepareSigner.call(this, ethers.Wallet.prototype);
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
      prepareSigner.call(this, new NonNativeSigner(this.signer.signingKey));
      this.mock = await this.helper.newAccount('$AccountERC7579Mock', [
        this.erc7579Validator,
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
      prepareSigner.call(this, new NonNativeSigner(this.signer.signingKey));
      this.mock = await this.helper.newAccount('$AccountERC7579Mock', [
        this.erc7579Validator,
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
