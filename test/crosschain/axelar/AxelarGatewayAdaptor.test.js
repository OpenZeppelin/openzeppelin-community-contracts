const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');

const ERC7786Attributes = require('../../helpers/erc7786attributes');

const AxelarHelper = require('./AxelarHelper');

async function fixture() {
  const [owner, sender, refundRecipient, ...accounts] = await ethers.getSigners();

  const { chain, axelar, gatewayA, gatewayB } = await AxelarHelper.deploy(owner);

  const receiver = await ethers.deployContract('$ERC7786ReceiverMock', [gatewayB]);
  const invalidReceiver = await ethers.deployContract('$ERC7786ReceiverInvalidMock');

  return { owner, sender, refundRecipient, accounts, chain, axelar, gatewayA, gatewayB, receiver, invalidReceiver };
}

describe('AxelarGateway', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('initial setup', async function () {
    await expect(this.gatewayA.gateway()).to.eventually.equal(this.axelar.gateway);
    await expect(this.gatewayA.gasService()).to.eventually.equal(this.axelar.gasService);
    await expect(this.gatewayA.getAxelarChain(this.chain.erc7930)).to.eventually.equal('local');
    await expect(this.gatewayA.getErc7930Chain('local')).to.eventually.equal(this.chain.erc7930);
    await expect(this.gatewayA.getRemoteGateway(this.chain.erc7930)).to.eventually.equal(
      this.gatewayB.target.toLowerCase(),
    );

    await expect(this.gatewayB.gateway()).to.eventually.equal(this.axelar.gateway);
    await expect(this.gatewayB.gasService()).to.eventually.equal(this.axelar.gasService);
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

    const sendId = '0x0000000000000000000000000000000000000000000000000000000000000001';

    await expect(this.gatewayA.connect(this.sender).sendMessage(erc7930Recipient, payload, attributes))
      .to.emit(this.gatewayA, 'MessageSent')
      .withArgs(sendId, erc7930Sender, erc7930Recipient, payload, 0n, attributes)
      .to.emit(this.axelar.gateway, 'ContractCall')
      .withArgs(this.gatewayA, 'local', this.gatewayB, ethers.keccak256(encoded), encoded)
      .to.emit(this.axelar.gateway, 'MessageExecuted')
      .withArgs(anyValue)
      .to.emit(this.receiver, 'MessageReceived')
      .withArgs(this.gatewayB, anyValue, erc7930Sender, payload);

    await expect(this.gatewayA.connect(this.sender).requestRelay(sendId, 0n, this.refundRecipient, { value: 1000n }))
      .to.emit(this.axelar.gasService, 'NativeGasPaidForContractCall')
      .withArgs(this.gatewayA, 'local', this.gatewayB, ethers.keccak256(encoded), 1000n, this.refundRecipient);
  });

  it('workflow (with requestRelay attribute)', async function () {
    const erc7930Sender = this.chain.toErc7930(this.sender);
    const erc7930Recipient = this.chain.toErc7930(this.receiver);
    const payload = ethers.randomBytes(128);
    const attributes = [
      ERC7786Attributes.encodeFunctionData('requestRelay', [1000n, 0n, this.refundRecipient.address]),
    ];
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
      ['bytes', 'bytes', 'bytes'],
      [erc7930Sender, erc7930Recipient, payload],
    );

    const sendId = '0x0000000000000000000000000000000000000000000000000000000000000000';

    await expect(
      this.gatewayA.connect(this.sender).sendMessage(erc7930Recipient, payload, attributes, { value: 1000n }),
    )
      .to.emit(this.gatewayA, 'MessageSent')
      .withArgs(sendId, erc7930Sender, erc7930Recipient, payload, 0n, attributes)
      .to.emit(this.axelar.gateway, 'ContractCall')
      .withArgs(this.gatewayA, 'local', this.gatewayB, ethers.keccak256(encoded), encoded)
      .to.emit(this.axelar.gateway, 'MessageExecuted')
      .withArgs(anyValue)
      .to.emit(this.axelar.gasService, 'NativeGasPaidForContractCall')
      .withArgs(this.gatewayA, 'local', this.gatewayB, ethers.keccak256(encoded), 1000n, this.refundRecipient)
      .to.emit(this.receiver, 'MessageReceived')
      .withArgs(this.gatewayB, anyValue, erc7930Sender, payload);
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
