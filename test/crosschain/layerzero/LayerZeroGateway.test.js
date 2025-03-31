const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');

const LayerZeroHelper = require('./LayerZeroHelper');

const getAddress = account => ethers.getAddress(account.target ?? account.address ?? account);

async function fixture() {
  const [owner, sender, ...accounts] = await ethers.getSigners();

  const { CAIP2, layerZeroChainId, layerZero, gatewayA, gatewayB } = await LayerZeroHelper.deploy(owner);

  const receiver = await ethers.deployContract('$ERC7786ReceiverMock', [gatewayB]);
  const invalidReceiver = await ethers.deployContract('$ERC7786ReceiverInvalidMock');

  const asCAIP10 = account => `${CAIP2}:${getAddress(account)}`;

  return {
    owner,
    sender,
    accounts,
    CAIP2,
    asCAIP10,
    layerZeroChainId,
    layerZero,
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
    await expect(this.gatewayA.endpoint()).to.eventually.equal(this.layerZero);
    await expect(this.gatewayA.fromCAIP2(this.CAIP2)).to.eventually.equal(this.layerZeroChainId);
    await expect(this.gatewayA.toCAIP2(this.layerZeroChainId)).to.eventually.equal(this.CAIP2);
    await expect(this.gatewayA.getRemoteGateway(this.CAIP2)).to.eventually.equal(
      LayerZeroHelper.toUniversalAddress(this.gatewayB),
    );

    await expect(this.gatewayB.endpoint()).to.eventually.equal(this.layerZero);
    await expect(this.gatewayB.fromCAIP2(this.CAIP2)).to.eventually.equal(this.layerZeroChainId);
    await expect(this.gatewayB.toCAIP2(this.layerZeroChainId)).to.eventually.equal(this.CAIP2);
    await expect(this.gatewayB.getRemoteGateway(this.CAIP2)).to.eventually.equal(
      LayerZeroHelper.toUniversalAddress(this.gatewayA),
    );
  });

  it('workflow', async function () {
    const srcCAIP10 = this.asCAIP10(this.sender);
    const dstCAIP10 = this.asCAIP10(this.receiver);
    const payload = ethers.randomBytes(128);
    const attributes = [];
    // const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
    //   ['bytes32', 'string', 'string', 'bytes', 'bytes[]'],
    //   [outboxId, getAddress(this.sender), getAddress(this.receiver), payload, attributes],
    // );

    await expect(
      this.gatewayA.connect(this.sender).sendMessage(this.CAIP2, getAddress(this.receiver), payload, attributes),
    )
      .to.emit(this.gatewayA, 'MessagePosted')
      .withArgs(outboxId, srcCAIP10, dstCAIP10, payload, attributes);

    await expect(this.gatewayA.finalize(outboxId, ethers.ZeroAddress))
      .to.emit(this.receiver, 'MessageReceived')
      .withArgs(this.gatewayB, anyValue, this.CAIP2, getAddress(this.sender), payload, attributes);
  });

  it('invalid receiver - bad return value', async function () {
    await this.gatewayA
      .connect(this.sender)
      .sendMessage(this.CAIP2, getAddress(this.invalidReceiver), ethers.randomBytes(128), []);

    await expect(this.gatewayA.finalize(outboxId, ethers.ZeroAddress)).to.be.revertedWithCustomError(
      this.gatewayB,
      'ReceiverExecutionFailed',
    );
  });

  it('invalid receiver - EOA', async function () {
    await this.gatewayA
      .connect(this.sender)
      .sendMessage(this.CAIP2, getAddress(this.accounts[0]), ethers.randomBytes(128), []);

    await expect(this.gatewayA.finalize(outboxId, ethers.ZeroAddress)).to.be.revertedWithoutReason();
  });
});
