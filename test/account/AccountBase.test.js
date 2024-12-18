const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ERC4337Helper } = require('../helpers/erc4337');
const { NonNativeSigner } = require('../helpers/signers');

const { shouldBehaveLikeAnAccountBase, shouldBehaveLikeAnAccountBaseExecutor } = require('./Account.behavior');

async function fixture() {
  // EOAs and environment
  const [beneficiary, other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-4337 signer and account
  const helper = new ERC4337Helper();
  await helper.wait();
  const signer = new NonNativeSigner({ sign: () => ({ serialized: '0x01' }) });
  const mock = await helper.newAccount('$AccountBaseMock', ['AccountBase', '1']);

  const signUserOp = async userOp => {
    userOp.signature = await signer.signMessage(userOp.hash());
    return userOp;
  };

  return { ...helper, mock, signer, target, beneficiary, other, signUserOp };
}

describe('AccountBase', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeAnAccountBase();
  shouldBehaveLikeAnAccountBaseExecutor();
});
