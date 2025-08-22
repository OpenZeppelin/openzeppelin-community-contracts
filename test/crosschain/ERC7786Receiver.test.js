const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');

const { getLocalChain } = require('@openzeppelin/contracts/test/helpers/chains');
const { generators } = require('@openzeppelin/contracts/test/helpers/random');

const payload = generators.hexBytes(128);
const attributes = [];

async function fixture() {
  const [sender, notAGateway] = await ethers.getSigners();
  const { toErc7930 } = await getLocalChain();

  const gateway = await ethers.deployContract('$ERC7786GatewayMock');
  const receiver = await ethers.deployContract('$ERC7786ReceiverMock', [gateway]);

  return { sender, notAGateway, gateway, receiver, toErc7930 };
}

// NOTE: here we are only testing the receiver. Failures of the gateway itself (invalid attributes, ...) are out of scope.
describe('ERC7786Receiver', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('nominal workflow', async function () {
    await expect(this.gateway.connect(this.sender).sendMessage(this.toErc7930(this.receiver), payload, attributes))
      .to.emit(this.gateway, 'MessageSent')
      .withArgs(ethers.ZeroHash, this.toErc7930(this.sender), this.toErc7930(this.receiver), payload, 0n, attributes)
      .to.emit(this.receiver, 'MessageReceived')
      .withArgs(this.gateway, anyValue, this.toErc7930(this.sender), payload, 0n); // ERC7786GatewayMock uses empty messageId
  });
});
