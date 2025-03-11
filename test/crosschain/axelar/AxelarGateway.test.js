const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');

const AxelarHelper = require('./AxelarHelper');

const getAddress = account => ethers.getAddress(account.target ?? account.address ?? account);

async function fixture() {
  const [owner, sender, ...accounts] = await ethers.getSigners();

  const { CAIP2, axelar, gatewayA, gatewayB } = await AxelarHelper.deploy(owner);

  const receiver = await ethers.deployContract('$ERC7786ReceiverMock', [gatewayB]);
  const invalidReceiver = await ethers.deployContract('$ERC7786ReceiverInvalidMock');

  const asCAIP10 = account => `${CAIP2}:${getAddress(account)}`;

  return { owner, sender, accounts, CAIP2, asCAIP10, axelar, gatewayA, gatewayB, receiver, invalidReceiver };
}

describe('AxelarGateway', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('initial setup', async function () {
    await expect(this.gatewayA.gateway()).to.eventually.equal(this.axelar);
    await expect(this.gatewayA.getEquivalentChain(this.CAIP2)).to.eventually.equal('local');
    await expect(this.gatewayA.getRemoteGateway(this.CAIP2)).to.eventually.equal(getAddress(this.gatewayB));

    await expect(this.gatewayB.gateway()).to.eventually.equal(this.axelar);
    await expect(this.gatewayB.getEquivalentChain(this.CAIP2)).to.eventually.equal('local');
    await expect(this.gatewayB.getRemoteGateway(this.CAIP2)).to.eventually.equal(getAddress(this.gatewayA));
  });

  it('workflow', async function () {
    const srcCAIP10 = this.asCAIP10(this.sender);
    const dstCAIP10 = this.asCAIP10(this.receiver);
    const payload = ethers.randomBytes(128);
    const attributes = [];
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
      ['string', 'string', 'bytes', 'bytes[]'],
      [getAddress(this.sender), getAddress(this.receiver), payload, attributes],
    );

    await expect(
      this.gatewayA.connect(this.sender).sendMessage(this.CAIP2, getAddress(this.receiver), payload, attributes),
    )
      .to.emit(this.gatewayA, 'MessagePosted')
      .withArgs(ethers.ZeroHash, srcCAIP10, dstCAIP10, payload, attributes)
      .to.emit(this.axelar, 'ContractCall')
      .withArgs(this.gatewayA, 'local', getAddress(this.gatewayB), ethers.keccak256(encoded), encoded)
      .to.emit(this.axelar, 'MessageExecuted')
      .withArgs(anyValue)
      .to.emit(this.receiver, 'MessageReceived')
      .withArgs(this.gatewayB, anyValue, this.CAIP2, getAddress(this.sender), payload, attributes);
  });

  it('invalid receiver - bad return value', async function () {
    await expect(
      this.gatewayA
        .connect(this.sender)
        .sendMessage(this.CAIP2, getAddress(this.invalidReceiver), ethers.randomBytes(128), []),
    ).to.be.revertedWithCustomError(this.gatewayB, 'ReceiverExecutionFailed');
  });

  it('invalid receiver - EOA', async function () {
    await expect(
      this.gatewayA
        .connect(this.sender)
        .sendMessage(this.CAIP2, getAddress(this.accounts[0]), ethers.randomBytes(128), []),
    ).to.be.revertedWithoutReason();
  });
});
