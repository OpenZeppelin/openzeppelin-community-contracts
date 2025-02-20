const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');

const AxelarHelper = require('./axelar/AxelarHelper');

const getAddress = account => ethers.getAddress(account.target ?? account.address ?? account);

const N = 3;
const M = 5;

async function fixture() {
  const [owner, sender, ...accounts] = await ethers.getSigners();

  const protocoles = await Promise.all(
    Array(M)
      .fill()
      .map(() => AxelarHelper.deploy(owner)),
  );

  const { CAIP2 } = protocoles.at(0);
  const asCAIP10 = account => `${CAIP2}:${getAddress(account)}`;

  const aggregatorA = await ethers.deployContract('ERC7786Aggregator', [
    owner,
    protocoles.map(({ gatewayA }) => gatewayA),
    N,
  ]);
  const aggregatorB = await ethers.deployContract('ERC7786Aggregator', [
    owner,
    protocoles.map(({ gatewayB }) => gatewayB),
    N,
  ]);
  await aggregatorA.registerRemoteRouter(CAIP2, getAddress(aggregatorB));
  await aggregatorB.registerRemoteRouter(CAIP2, getAddress(aggregatorA));

  const receiver = await ethers.deployContract('$ERC7786ReceiverMock', [aggregatorB]);
  const invalidReceiver = await ethers.deployContract('$ERC7786ReceiverInvalidMock');

  return { owner, sender, accounts, CAIP2, asCAIP10, protocoles, aggregatorA, aggregatorB, receiver, invalidReceiver };
}

describe('ERC7786Aggregator', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('initial setup', async function () {
    await expect(this.aggregatorA.getGateways()).to.eventually.deep.equal(
      this.protocoles.map(({ gatewayA }) => getAddress(gatewayA)),
    );
    await expect(this.aggregatorA.getThreshold()).to.eventually.equal(N);
    await expect(this.aggregatorA.getRemoteRouter(this.CAIP2)).to.eventually.equal(getAddress(this.aggregatorB));

    await expect(this.aggregatorB.getGateways()).to.eventually.deep.equal(
      this.protocoles.map(({ gatewayB }) => getAddress(gatewayB)),
    );
    await expect(this.aggregatorB.getThreshold()).to.eventually.equal(N);
    await expect(this.aggregatorB.getRemoteRouter(this.CAIP2)).to.eventually.equal(getAddress(this.aggregatorA));
  });

  describe('cross chain call', function () {
    it('valid receiver', async function () {
      this.destination = this.receiver;
      this.payload = ethers.randomBytes(128);
      this.attributes = [];
      this.success = true;
    });

    it('invalid receiver - bad return value', async function () {
      this.destination = this.invalidReceiver;
      this.payload = ethers.randomBytes(128);
      this.attributes = [];
      this.success = false;
    });

    it('invalid receiver - EOA', async function () {
      this.destination = this.accounts[0];
      this.payload = ethers.randomBytes(128);
      this.attributes = [];
      this.success = false;
    });

    afterEach(async function () {
      const tx = await this.aggregatorA
        .connect(this.sender)
        .sendMessage(this.CAIP2, getAddress(this.destination), this.payload, this.attributes);
      const { logs } = await tx.wait();
      const [resultId] = logs.find(ev => ev?.fragment?.name == 'Received').args;

      // Message was posted
      await expect(tx)
        .to.emit(this.aggregatorA, 'MessagePosted')
        .withArgs(
          ethers.ZeroHash,
          this.asCAIP10(this.sender),
          this.asCAIP10(this.destination),
          this.payload,
          this.attributes,
        );

      // MessagePosted to all gateways on the A side and received from all gateways on the B side
      for (const { gatewayA, gatewayB } of this.protocoles) {
        await expect(tx)
          .to.emit(gatewayA, 'MessagePosted')
          .withArgs(
            ethers.ZeroHash,
            this.asCAIP10(this.aggregatorA),
            this.asCAIP10(this.aggregatorB),
            anyValue,
            anyValue,
          )
          .to.emit(this.aggregatorB, 'Received')
          .withArgs(resultId, gatewayB);
      }

      if (this.success) {
        await expect(tx)
          .to.emit(this.destination, 'MessageReceived')
          .withArgs(this.aggregatorB, this.CAIP2, getAddress(this.sender), this.payload, this.attributes)
          .to.emit(this.aggregatorB, 'ExecutionSuccess')
          .withArgs(resultId)
          .to.not.emit(this.aggregatorB, 'ExecutionFailed');

        // Number of times the execution succeeded
        expect(logs.filter(ev => ev?.fragment?.name == 'ExecutionSuccess').length).to.equal(1);
      } else {
        await expect(tx)
          .to.emit(this.aggregatorB, 'ExecutionFailed')
          .withArgs(resultId)
          .to.not.emit(this.aggregatorB, 'ExecutionSuccess');

        // Number of times the execution failed
        expect(logs.filter(ev => ev?.fragment?.name == 'ExecutionFailed').length).to.equal(M - N + 1);
      }
    });
  });
});
