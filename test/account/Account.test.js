const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ERC4337Helper } = require('../helpers/erc4337');
const { NonNativeSigner } = require('../helpers/signers');

const {
  shouldBehaveLikeAccountCore,
  shouldBehaveLikeAccountERC7821,
  shouldBehaveLikeAccountHolder,
} = require('./Account.behavior');

async function fixture() {
  // EOAs and environment
  const [beneficiary, other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-4337 signer
  const signer = new NonNativeSigner({ sign: () => ({ serialized: '0x01' }) });

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const mock = await helper.newAccount('$AccountMock', ['Account', '1']);

  const signUserOp = async userOp => {
    userOp.signature = await signer.signMessage(userOp.hash());
    return userOp;
  };

  return { ...env, mock, signer, target, beneficiary, other, signUserOp };
}

describe('Account', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeAccountCore();
  shouldBehaveLikeAccountERC7821();
  shouldBehaveLikeAccountHolder();
});
