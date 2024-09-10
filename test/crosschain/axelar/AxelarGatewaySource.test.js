const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

async function fixture() {
  const mock = await ethers.deployContract('$AxelarGatewaySource');
  return { mock };
}

describe('AxelarGatewaySource', function () {
  before(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('_execute', function () {
    // TODO: Add tests
  });
});
