const { ethers } = require('hardhat');
const { shouldBehaveLikeAnAccountBase, shouldBehaveLikeAnAccountBaseExecutor } = require('./Account.behavior');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ERC4337Helper } = require('../helpers/erc4337');
const { NonNativeSigner } = require('../helpers/signers');

async function fixture() {
  const [beneficiary, other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');
  const signer = new NonNativeSigner({ sign: () => ({ serialized: '0x01' }) });
  const helper = new ERC4337Helper('$AccountBaseMock');
  const smartAccount = await helper.newAccount(['AccountBase', '1']);
  const signUserOp = async userOp => {
    userOp.signature = await signer.signMessage(userOp.hash());
    return userOp;
  };

  return { ...helper, mock: smartAccount, signer, target, beneficiary, other, signUserOp };
}

describe('AccountBase', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeAnAccountBase();
  shouldBehaveLikeAnAccountBaseExecutor();
});
