const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');

const AxelarHelper = require('./AxelarHelper');

async function fixture() {
  const [owner, sender, ...accounts] = await ethers.getSigners();

  const { chain, axelar, gatewayA, gatewayB } = await AxelarHelper.deploy(owner);

  const receiver = await ethers.deployContract('$ERC7786ReceiverMock', [gatewayB]);
  const invalidReceiver = await ethers.deployContract('$ERC7786ReceiverInvalidMock');

  return { owner, sender, accounts, chain, axelar, gatewayA, gatewayB, receiver, invalidReceiver };
}

describe('AxelarGatewayAdapter', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('initial setup', async function () {
    await expect(this.gatewayA.gateway()).to.eventually.equal(this.axelar);
    await expect(this.gatewayA.getAxelarChain(this.chain.erc7930)).to.eventually.equal('local');
    await expect(this.gatewayA.getErc7930Chain('local')).to.eventually.equal(this.chain.erc7930);
    await expect(this.gatewayA.getRemoteGateway(this.chain.erc7930)).to.eventually.equal(
      this.gatewayB.target.toLowerCase(),
    );

    await expect(this.gatewayB.gateway()).to.eventually.equal(this.axelar);
    await expect(this.gatewayB.getAxelarChain(this.chain.erc7930)).to.eventually.equal('local');
    await expect(this.gatewayB.getErc7930Chain('local')).to.eventually.equal(this.chain.erc7930);
    await expect(this.gatewayB.getRemoteGateway(this.chain.erc7930)).to.eventually.equal(
      this.gatewayA.target.toLowerCase(),
    );
  });

  it('workflow', async function () {
    const erc7930Sender = this.chain.toErc7930(this.sender);
    const erc7930Recipient = this.chain.toErc7930(this.receiver);
    const payload = ethers.randomBytes(128);
    const attributes = [];
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
      ['bytes', 'bytes', 'bytes'],
      [erc7930Sender, erc7930Recipient, payload],
    );

    await expect(this.gatewayA.connect(this.sender).sendMessage(erc7930Recipient, payload, attributes))
      .to.emit(this.gatewayA, 'MessageSent')
      .withArgs(ethers.ZeroHash, erc7930Sender, erc7930Recipient, payload, 0n, attributes)
      .to.emit(this.axelar, 'ContractCall')
      .withArgs(this.gatewayA, 'local', this.gatewayB, ethers.keccak256(encoded), encoded)
      .to.emit(this.axelar, 'MessageExecuted')
      .withArgs(anyValue)
      .to.emit(this.receiver, 'MessageReceived')
      .withArgs(this.gatewayB, anyValue, erc7930Sender, payload, 0n);
  });

  it('invalid receiver - bad return value', async function () {
    await expect(
      this.gatewayA
        .connect(this.sender)
        .sendMessage(this.chain.toErc7930(this.invalidReceiver), ethers.randomBytes(128), []),
    ).to.be.revertedWithCustomError(this.gatewayB, 'ReceiverExecutionFailed');
  });

  it('invalid receiver - EOA', async function () {
    await expect(
      this.gatewayA
        .connect(this.sender)
        .sendMessage(this.chain.toErc7930(this.accounts[0]), ethers.randomBytes(128), []),
    ).to.be.revertedWithoutReason();
  });
});
