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

  const { chain } = protocoles.at(0);

  const bridgeA = await ethers.deployContract('ERC7786OpenBridge', [
    owner,
    protocoles.map(({ gatewayA }) => gatewayA),
    N,
  ]);
  const bridgeB = await ethers.deployContract('ERC7786OpenBridge', [
    owner,
    protocoles.map(({ gatewayB }) => gatewayB),
    N,
  ]);
  await bridgeA.registerRemoteBridge(chain.toErc7930(bridgeB));
  await bridgeB.registerRemoteBridge(chain.toErc7930(bridgeA));

  return { owner, sender, accounts, chain, protocoles, bridgeA, bridgeB };
}

describe('ERC7786OpenBridge', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('initial setup', async function () {
    await expect(this.bridgeA.getGateways()).to.eventually.deep.equal(
      this.protocoles.map(({ gatewayA }) => getAddress(gatewayA)),
    );
    await expect(this.bridgeA.getThreshold()).to.eventually.equal(N);
    await expect(this.bridgeA.getRemoteBridge(this.chain.erc7930)).to.eventually.equal(
      this.chain.toErc7930(this.bridgeB),
    );

    await expect(this.bridgeB.getGateways()).to.eventually.deep.equal(
      this.protocoles.map(({ gatewayB }) => getAddress(gatewayB)),
    );
    await expect(this.bridgeB.getThreshold()).to.eventually.equal(N);
    await expect(this.bridgeB.getRemoteBridge(this.chain.erc7930)).to.eventually.equal(
      this.chain.toErc7930(this.bridgeA),
    );
  });

  describe('cross chain call', function () {
    it('valid receiver', async function () {
      this.destination = await ethers.deployContract('$ERC7786ReceiverMock', [this.bridgeB]);
      this.payload = ethers.randomBytes(128);
      this.attributes = [];
      this.opts = {};
      this.outcome = true; // execution success
    });

    it('with attributes', async function () {
      this.destination = this.accounts[0];
      this.payload = ethers.randomBytes(128);
      this.attributes = [ethers.randomBytes(32)];
      this.opts = {};
      this.outcome = 'UnsupportedAttribute';
    });

    it('with value', async function () {
      this.destination = this.accounts[0];
      this.payload = ethers.randomBytes(128);
      this.attributes = [];
      this.opts = { value: 1n };
      this.outcome = 'UnsupportedNativeTransfer';
    });

    it('invalid receiver - receiver revert', async function () {
      this.destination = await ethers.deployContract('$ERC7786ReceiverRevertMock');
      this.payload = ethers.randomBytes(128);
      this.attributes = [];
      this.opts = {};
      this.outcome = false; // execution failed
    });

    it('invalid receiver - bad return value', async function () {
      this.destination = await ethers.deployContract('$ERC7786ReceiverInvalidMock');
      this.payload = ethers.randomBytes(128);
      this.attributes = [];
      this.opts = {};
      this.outcome = 'ERC7786OpenBridgeInvalidExecutionReturnValue'; // revert with custom error
    });

    it('invalid receiver - EOA', async function () {
      this.destination = this.accounts[0];
      this.payload = ethers.randomBytes(128);
      this.attributes = [];
      this.opts = {};
      this.outcome = 'ERC7786OpenBridgeInvalidExecutionReturnValue'; // revert with custom error
    });

    afterEach(async function () {
      const txPromise = this.bridgeA
        .connect(this.sender)
        .sendMessage(this.chain.toErc7930(this.destination), this.payload, this.attributes, this.opts ?? {});

      switch (typeof this.outcome) {
        case 'string': {
          await expect(txPromise).to.be.revertedWithCustomError(this.bridgeB, this.outcome);
          break;
        }
        case 'boolean': {
          const { logs } = await txPromise.then(tx => tx.wait());
          const [resultId] = logs.find(ev => ev?.fragment?.name == 'Received').args;

          // Message was posted
          await expect(txPromise)
            .to.emit(this.bridgeA, 'MessageSent')
            .withArgs(
              ethers.ZeroHash,
              this.chain.toErc7930(this.sender),
              this.chain.toErc7930(this.destination),
              this.payload,
              0n,
              this.attributes,
            );

          // MessagePosted to all gateways on the A side and received from all gateways on the B side
          for (const { gatewayA, gatewayB } of this.protocoles) {
            await expect(txPromise)
              .to.emit(gatewayA, 'MessageSent')
              .withArgs(
                ethers.ZeroHash,
                this.chain.toErc7930(this.bridgeA),
                this.chain.toErc7930(this.bridgeB),
                anyValue,
                0n,
                anyValue,
              )
              .to.emit(this.bridgeB, 'Received')
              .withArgs(resultId, gatewayB);
          }

          if (this.outcome) {
            await expect(txPromise)
              .to.emit(this.destination, 'MessageReceived')
              .withArgs(this.bridgeB, anyValue, this.chain.toErc7930(this.sender), this.payload, 0n)
              .to.emit(this.bridgeB, 'ExecutionSuccess')
              .withArgs(resultId)
              .to.not.emit(this.bridgeB, 'ExecutionFailed');

            // Number of times the execution succeeded
            expect(logs.filter(ev => ev?.fragment?.name == 'ExecutionSuccess').length).to.equal(1);
          } else {
            await expect(txPromise)
              .to.emit(this.bridgeB, 'ExecutionFailed')
              .withArgs(resultId)
              .to.not.emit(this.bridgeB, 'ExecutionSuccess');

            // Number of times the execution failed
            expect(logs.filter(ev => ev?.fragment?.name == 'ExecutionFailed').length).to.equal(M - N + 1);
          }
          break;
        }
      }
    });
  });
});
