const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');

const ERC7786Attributes = require('../../helpers/erc7786attributes');
const WormholeHelper = require('./WormholeHelper');

const value = 1_000n;

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

describe('WormholeGatewayAdapter', function () {
  const sendId = '0x0000000000000000000000000000000000000000000000000000000000000001';

  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('initial setup', async function () {
    await expect(this.gatewayA.relayer()).to.eventually.equal(this.wormhole);
    await expect(this.gatewayA.getChainId(this.wormholeChainId)).to.eventually.equal(this.chain.reference);
    await expect(this.gatewayA.getWormholeChain(ethers.Typed.bytes(this.chain.erc7930))).to.eventually.equal(
      this.wormholeChainId,
    );
    await expect(this.gatewayA.getWormholeChain(ethers.Typed.uint256(this.chain.reference))).to.eventually.equal(
      this.wormholeChainId,
    );
    await expect(this.gatewayA.getRemoteGateway(ethers.Typed.bytes(this.chain.erc7930))).to.eventually.equal(
      this.gatewayB,
    );
    await expect(this.gatewayA.getRemoteGateway(ethers.Typed.uint256(this.chain.reference))).to.eventually.equal(
      this.gatewayB,
    );

    await expect(this.gatewayB.relayer()).to.eventually.equal(this.wormhole);
    await expect(this.gatewayB.getChainId(this.wormholeChainId)).to.eventually.equal(this.chain.reference);
    await expect(this.gatewayB.getWormholeChain(ethers.Typed.bytes(this.chain.erc7930))).to.eventually.equal(
      this.wormholeChainId,
    );
    await expect(this.gatewayB.getWormholeChain(ethers.Typed.uint256(this.chain.reference))).to.eventually.equal(
      this.wormholeChainId,
    );
    await expect(this.gatewayB.getRemoteGateway(ethers.Typed.bytes(this.chain.erc7930))).to.eventually.equal(
      this.gatewayA,
    );
    await expect(this.gatewayB.getRemoteGateway(ethers.Typed.uint256(this.chain.reference))).to.eventually.equal(
      this.gatewayA,
    );
  });

  it('workflow', async function () {
    const erc7930Sender = this.chain.toErc7930(this.sender);
    const erc7930Recipient = this.chain.toErc7930(this.receiver);
    const payload = ethers.randomBytes(128);
    const attributes = [];
    // const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
    //   ['bytes32', 'string', 'string', 'bytes', 'bytes[]'],
    //   [sendId, getAddress(this.sender), getAddress(this.receiver), payload, attributes],
    // );

    await expect(this.gatewayA.connect(this.sender).sendMessage(erc7930Recipient, payload, attributes, { value }))
      .to.emit(this.gatewayA, 'MessageSent')
      .withArgs(sendId, erc7930Sender, erc7930Recipient, payload, value, attributes);

    await expect(this.gatewayA.requestRelay(sendId, 100_000n, ethers.ZeroAddress))
      .to.emit(this.gatewayA, 'MessageRelayed')
      .withArgs(sendId)
      .to.emit(this.receiver, 'MessageReceived')
      .withArgs(this.gatewayB, anyValue, erc7930Sender, payload, value);
  });

  it('workflow - requestRelay attribute', async function () {
    const erc7930Sender = this.chain.toErc7930(this.sender);
    const erc7930Recipient = this.chain.toErc7930(this.receiver);
    const payload = ethers.randomBytes(128);
    const attributes = [ERC7786Attributes.encodeFunctionData('requestRelay', [value, 100_000n, ethers.ZeroAddress])];
    // const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
    //   ['bytes32', 'string', 'string', 'bytes', 'bytes[]'],
    //   [sendId, getAddress(this.sender), getAddress(this.receiver), payload, attributes],
    // );

    await expect(this.gatewayA.connect(this.sender).sendMessage(erc7930Recipient, payload, attributes, { value }))
      .to.emit(this.gatewayA, 'MessageSent')
      .withArgs(0n, erc7930Sender, erc7930Recipient, payload, value, attributes)
      .to.emit(this.receiver, 'MessageReceived')
      .withArgs(this.gatewayB, anyValue, erc7930Sender, payload, value);
  });

  it('invalid receiver - bad return value', async function () {
    await this.gatewayA
      .connect(this.sender)
      .sendMessage(this.chain.toErc7930(this.invalidReceiver), ethers.randomBytes(128), []);

    await expect(this.gatewayA.requestRelay(sendId, 100_000n, ethers.ZeroAddress)).to.be.revertedWithCustomError(
      this.gatewayB,
      'ReceiverExecutionFailed',
    );
  });

  it('invalid receiver - EOA', async function () {
    await this.gatewayA
      .connect(this.sender)
      .sendMessage(this.chain.toErc7930(this.accounts[0]), ethers.randomBytes(128), []);

    await expect(this.gatewayA.requestRelay(sendId, 100_000n, ethers.ZeroAddress)).to.be.revertedWithoutReason();
  });

  it('invalid sendId', async function () {
    await expect(this.gatewayA.requestRelay(sendId, 100_000n, ethers.ZeroAddress))
      .to.be.revertedWithCustomError(this.gatewayA, 'InvalidSendId')
      .withArgs(sendId);
  });
});
