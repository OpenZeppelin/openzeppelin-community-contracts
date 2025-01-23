const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { shouldBehaveLikePaymaster } = require('./Paymaster.behavior');

async function fixture() {
  const [depositor, staker, receiver] = await ethers.getSigners();

  const mock = await ethers.deployContract('$PaymasterCoreMock');

  return {
    depositor,
    staker,
    receiver,
    mock,
  };
}

describe('PaymasterCore', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikePaymaster();
});
