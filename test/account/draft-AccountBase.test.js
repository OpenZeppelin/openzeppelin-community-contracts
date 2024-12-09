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
  const smartAccount = await helper.newAccount();

  return { ...helper, mock: smartAccount, signer, target, beneficiary, other };
}

describe('AccountBase', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeAnAccountBase();
  shouldBehaveLikeAnAccountBaseExecutor();
});
