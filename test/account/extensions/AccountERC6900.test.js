const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ERC4337Helper } = require('../../helpers/erc4337');
const { PackedUserOperation } = require('../../helpers/eip712-types');

const { shouldBehaveLikeAccountCore } = require('../Account.behavior');
const { shouldBehaveLikeAccountERC6900 } = require('./AccountERC6900.behavior');
// const { shouldBehaveLikeERC7739 } = require('../../utils/cryptography/ERC7739.behavior');

async function fixture() {
  // EOAs and environment
  const [other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');
  const anotherTarget = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-6900 validator
  const validatorMock = await ethers.deployContract('$ERC6900ValidationMock');

  // ERC-4337 signer
  const signer = ethers.Wallet.createRandom();

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const mock = await helper.newAccount('$AccountERC6900Mock', [
    'AccountERC6900',
    '1',
    validatorMock.target,
    ethers.solidityPacked(['address'], [signer.address]),
  ]);

  // domain cannot be fetched using getDomain(mock) before the mock is deployed
  const domain = {
    name: 'AccountERC6900',
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

describe('AccountERC6900', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  // shouldBehaveLikeAccountCore();
  shouldBehaveLikeAccountERC6900();
});
