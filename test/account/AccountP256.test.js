const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ERC4337Helper } = require('../helpers/erc4337');
const { NonNativeSigner, P256SigningKey } = require('../helpers/signers');
const { PackedUserOperation } = require('../helpers/eip712-types');

const {
  shouldBehaveLikeAccountCore,
  shouldBehaveLikeAccountERC7821,
  shouldBehaveLikeAccountHolder,
} = require('./Account.behavior');
const { shouldBehaveLikeERC7739Signer } = require('../utils/cryptography/ERC7739Signer.behavior');

async function fixture() {
  // EOAs and environment
  const [beneficiary, other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-4337 signer
  const signer = new NonNativeSigner(P256SigningKey.random());

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const mock = await helper.newAccount('$AccountP256Mock', [
    'AccountP256',
    '1',
    signer.signingKey.publicKey.qx,
    signer.signingKey.publicKey.qy,
  ]);

  // domain cannot be fetched using getDomain(mock) before the mock is deployed
  const domain = {
    name: 'AccountP256',
    version: '1',
    chainId: env.chainId,
    verifyingContract: mock.address,
  };

  const signUserOp = userOp =>
    signer
      .signTypedData(domain, { PackedUserOperation }, userOp.packed)
      .then(signature => Object.assign(userOp, { signature }));

  return { ...env, mock, domain, signer, target, beneficiary, other, signUserOp };
}

describe('AccountP256', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeAccountCore();
  shouldBehaveLikeAccountERC7821();
  shouldBehaveLikeAccountHolder();

  describe('ERC7739Signer', function () {
    beforeEach(async function () {
      this.mock = await this.mock.deploy();
      this.signTypedData = this.signer.signTypedData.bind(this.signer);
    });

    shouldBehaveLikeERC7739Signer();
  });
});
