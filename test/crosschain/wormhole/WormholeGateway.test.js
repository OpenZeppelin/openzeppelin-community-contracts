const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');

const WormholeHelper = require('./WormholeHelper');

async function fixture() {
  const [owner, sender, ...accounts] = await ethers.getSigners();

  const { chain, wormholeChainId, wormhole, gatewayA, gatewayB } = await WormholeHelper.deploy(owner);

  const receiver = await ethers.deployContract('$ERC7786ReceiverMock', [gatewayB]);
  const invalidReceiver = await ethers.deployContract('$ERC7786ReceiverInvalidMock');

  return {
    owner,
    sender,
    accounts,
    chain,
    wormholeChainId,
    wormhole,
    gatewayA,
    gatewayB,
    receiver,
    invalidReceiver,
  };
}

describe('WormholeGateway', function () {
  const outboxId = '0x0000000000000000000000000000000000000000000000000000000000000001';

  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('initial setup', async function () {
    await expect(this.gatewayA.relayer()).to.eventually.equal(this.wormhole);
    await expect(this.gatewayA.getWormholeChain(this.chain.erc7930)).to.eventually.equal(this.wormholeChainId);
    await expect(this.gatewayA.getErc7930Chain(this.wormholeChainId)).to.eventually.equal(this.chain.erc7930);
    await expect(this.gatewayA.getRemoteGateway(this.chain.erc7930)).to.eventually.equal(
      WormholeHelper.toUniversalAddress(this.gatewayB),
    );

    await expect(this.gatewayB.relayer()).to.eventually.equal(this.wormhole);
    await expect(this.gatewayB.getWormholeChain(this.chain.erc7930)).to.eventually.equal(this.wormholeChainId);
    await expect(this.gatewayB.getErc7930Chain(this.wormholeChainId)).to.eventually.equal(this.chain.erc7930);
    await expect(this.gatewayB.getRemoteGateway(this.chain.erc7930)).to.eventually.equal(
      WormholeHelper.toUniversalAddress(this.gatewayA),
    );
  });

  it('workflow', async function () {
    const erc7930Sender = this.chain.toErc7930(this.sender);
    const erc7930Recipient = this.chain.toErc7930(this.receiver);
    const payload = ethers.randomBytes(128);
    const attributes = [];
    // const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
    //   ['bytes32', 'string', 'string', 'bytes', 'bytes[]'],
    //   [outboxId, getAddress(this.sender), getAddress(this.receiver), payload, attributes],
    // );

    await expect(this.gatewayA.connect(this.sender).sendMessage(erc7930Recipient, payload, attributes))
      .to.emit(this.gatewayA, 'MessageSent')
      .withArgs(outboxId, erc7930Sender, erc7930Recipient, payload, 0n, attributes);

    await expect(this.gatewayA.finalizeEvmMessage(outboxId, 100_000n))
      .to.emit(this.receiver, 'MessageReceived')
      .withArgs(this.gatewayB, anyValue, erc7930Sender, payload);
  });

  it('invalid receiver - bad return value', async function () {
    await this.gatewayA
      .connect(this.sender)
      .sendMessage(this.chain.toErc7930(this.invalidReceiver), ethers.randomBytes(128), []);

    await expect(this.gatewayA.finalizeEvmMessage(outboxId, 100_000n)).to.be.revertedWithCustomError(
      this.gatewayB,
      'ReceiverExecutionFailed',
    );
  });

  it('invalid receiver - EOA', async function () {
    await this.gatewayA
      .connect(this.sender)
      .sendMessage(this.chain.toErc7930(this.accounts[0]), ethers.randomBytes(128), []);

    await expect(this.gatewayA.finalizeEvmMessage(outboxId, 100_000n)).to.be.revertedWithoutReason();
  });
});
