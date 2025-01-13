const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ERC4337Helper } = require('../../helpers/erc4337');
const { PackedUserOperation } = require('../../helpers/eip712-types');

const { shouldBehaveLikeAccountCore } = require('../Account.behavior');
const { shouldBehaveLikeAccountERC7579 } = require('./AccountERC7579.behavior');
const { shouldBehaveLikeERC7739 } = require('../../utils/cryptography/ERC7739.behavior');

async function fixture() {
  // EOAs and environment
  const [other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');
  const anotherTarget = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-7579 validator
  const validatorMock = await ethers.deployContract('$ERC7579ValidatorMock');

  // ERC-4337 signer
  const signer = ethers.Wallet.createRandom();

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const mock = await helper.newAccount('$AccountERC7579HookedMock', [
    'AccountERC7579Hooked',
    '1',
    validatorMock.target,
    ethers.solidityPacked(['address'], [signer.address]),
  ]);

  // domain cannot be fetched using getDomain(mock) before the mock is deployed
  const domain = {
    name: 'AccountERC7579Hooked',
    version: '1',
    chainId: env.chainId,
    verifyingContract: mock.address,
  };

  const signUserOp = userOp =>
    signer
      .signTypedData(domain, { PackedUserOperation }, userOp.packed)
      .then(signature => Object.assign(userOp, { signature }));

  const userOp = {
    // Use the first 20 bytes from the nonce key (24 bytes) to identify the validator module
    nonce: ethers.zeroPadBytes(ethers.hexlify(validatorMock.target), 32),
  };

  return { ...env, validatorMock, mock, domain, signer, target, anotherTarget, other, signUserOp, userOp };
}

describe('AccountERC7579Hooked', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeAccountCore();
  shouldBehaveLikeAccountERC7579({ withHooks: true });

  describe('ERC7739', function () {
    beforeEach(async function () {
      this.mock = await this.mock.deploy();
      // Use the first 20 bytes from the signature to identify the validator module
      this.signTypedData ??= (...args) =>
        this.signer
          .signTypedData(...args)
          .then(signature => ethers.solidityPacked(['address', 'bytes'], [this.validatorMock.target, signature]));
    });

    shouldBehaveLikeERC7739();
  });
});
