const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { getLocalCAIP } = require('@openzeppelin/contracts/test/helpers/chains');
const { generators } = require('@openzeppelin/contracts/test/helpers/random');

const payload = generators.hexBytes(128);
const attributes = [];

const getAddress = account => ethers.getAddress(account.target ?? account.address ?? account);

async function fixture() {
  const [sender, notAGateway] = await ethers.getSigners();
  const { caip2, toCaip10 } = await getLocalCAIP();

  const gateway = await ethers.deployContract('$ERC7786GatewayMock');
  const receiver = await ethers.deployContract('$ERC7786ReceiverMock', [gateway]);

  return { sender, notAGateway, gateway, receiver, caip2, toCaip10 };
}

// NOTE: here we are only testing the receiver. Failures of the gateway itself (invalid attributes, ...) are out of scope.
describe('ERC7786Receiver', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('nominal workflow', async function () {
    await expect(
      this.gateway.connect(this.sender).sendMessage(this.caip2, getAddress(this.receiver), payload, attributes),
    )
      .to.emit(this.gateway, 'MessagePosted')
      .withArgs(ethers.ZeroHash, this.toCaip10(this.sender), this.toCaip10(this.receiver), payload, attributes)
      .to.emit(this.receiver, 'MessageReceived')
      .withArgs(this.gateway, this.caip2, getAddress(this.sender), payload, attributes);
  });
});
