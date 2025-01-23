const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { shouldBehaveLikePaymaster } = require('./Paymaster.behavior');

async function fixture() {
  const [depositor, staker, receiver] = await ethers.getSigners();

  const signer = ethers.Wallet.createRandom();
  const mock = await ethers.deployContract('$PaymasterSignerECDSAMock', [signer]);

  return {
    depositor,
    staker,
    receiver,
    mock,
  };
}

describe('PaymasterSigner', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikePaymaster();
});
