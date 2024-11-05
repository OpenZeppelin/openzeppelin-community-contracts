const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');

const getAddress = account => ethers.getAddress(account.target ?? account.address ?? account);

async function fixture() {
  const [owner, sender, ...accounts] = await ethers.getSigners();

  const { chainId } = await ethers.provider.getNetwork();
  const CAIP2 = `eip155:${chainId}`;
  const asCAIP10 = account => `eip155:${chainId}:${getAddress(account)}`;

  const axelar          = await ethers.deployContract('$AxelarGatewayMock');
  const srcGateway      = await ethers.deployContract('$AxelarGatewaySource', [ owner, axelar ]);
  const dstGateway      = await ethers.deployContract('$AxelarGatewayDestination', [ owner, axelar, axelar ]);
  const receiver        = await ethers.deployContract('$ERC7786ReceiverMock', [ dstGateway ]);
  const invalidReceiver = await ethers.deployContract('$ERC7786ReceiverInvalidMock');

  await srcGateway.registerChainEquivalence(CAIP2, 'local');
  await dstGateway.registerChainEquivalence(CAIP2, 'local');
  await srcGateway.registerRemoteGateway(CAIP2, getAddress(dstGateway));
  await dstGateway.registerRemoteGateway(CAIP2, getAddress(srcGateway));

  return { owner, sender, accounts, CAIP2, asCAIP10, axelar, srcGateway, dstGateway, receiver, invalidReceiver };
}

describe('AxelarGateway', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('initial setup', async function () {
    expect(this.srcGateway.localGateway()).to.eventually.equal(this.axelar);
    expect(this.srcGateway.getEquivalentChain(this.CAIP2)).to.eventually.equal('local');
    expect(this.srcGateway.getRemoteGateway(this.CAIP2)).to.eventually.equal(getAddress(this.dstGateway));

    expect(this.dstGateway.localGateway()).to.eventually.equal(this.axelar);
    expect(this.dstGateway.getEquivalentChain(this.CAIP2)).to.eventually.equal('local');
    expect(this.dstGateway.getRemoteGateway(this.CAIP2)).to.eventually.equal(getAddress(this.srcGateway));
  });

  describe('Active mode', function () {
    beforeEach(async function () {
      await this.axelar.setActive(true);
    });

    it('workflow', async function () {
      const srcCAIP10  = this.asCAIP10(this.sender);
      const dstCAIP10  = this.asCAIP10(this.receiver);
      const payload    = ethers.randomBytes(128);
      const attributes = [];
      const package    = ethers.AbiCoder.defaultAbiCoder().encode([ 'string', 'string', 'bytes', 'bytes[]' ], [ getAddress(this.sender), getAddress(this.receiver), payload, attributes ]);

      await expect(this.srcGateway.connect(this.sender).sendMessage(this.CAIP2, getAddress(this.receiver), payload, attributes))
        .to.emit(this.srcGateway, 'MessagePosted').withArgs(ethers.ZeroHash, srcCAIP10, dstCAIP10, payload, attributes)
        .to.emit(this.axelar, 'ContractCall').withArgs(this.srcGateway, 'local', getAddress(this.dstGateway), ethers.keccak256(package), package)
        .to.emit(this.axelar, 'ContractCallExecuted').withArgs(anyValue)
        .to.emit(this.receiver, 'MessageReceived').withArgs(ethers.ZeroAddress, this.CAIP2, getAddress(this.sender), payload, attributes);
    });

    it('invalid receiver - bad return value', async function () {
      await expect(this.srcGateway.connect(this.sender).sendMessage(
        this.CAIP2,
        getAddress(this.invalidReceiver),
        ethers.randomBytes(128),
        [],
      ))
        .to.be.revertedWith('Receiver execution failed');
    });

    it('invalid receiver - EOA', async function () {
      await expect(this.srcGateway.connect(this.sender).sendMessage(
        this.CAIP2,
        getAddress(this.accounts[0]),
        ethers.randomBytes(128),
        [],
      ))
        .to.be.revertedWithoutReason();
    });
  });

  describe('Passive mode', function () {
    beforeEach(async function () {
      await this.axelar.setActive(false);
    });

    it('workflow', async function () {
      const srcCAIP10  = this.asCAIP10(this.sender);
      const dstCAIP10  = this.asCAIP10(this.receiver);
      const payload    = ethers.randomBytes(128);
      const attributes = [];
      const package    = ethers.AbiCoder.defaultAbiCoder().encode([ 'string', 'string', 'bytes', 'bytes[]' ], [ getAddress(this.sender), getAddress(this.receiver), payload, attributes ]);

      const tx = await this.srcGateway.connect(this.sender).sendMessage(this.CAIP2, getAddress(this.receiver), payload, attributes);
      await expect(tx)
        .to.emit(this.srcGateway, 'MessagePosted').withArgs(ethers.ZeroHash, srcCAIP10, dstCAIP10, payload, attributes)
        .to.emit(this.axelar, 'ContractCall').withArgs(this.srcGateway, 'local', getAddress(this.dstGateway), ethers.keccak256(package), package)
        .to.emit(this.axelar, 'CommandIdPending').withArgs(anyValue, 'local', getAddress(this.dstGateway), package);

      const { logs } = await tx.wait();
      const commandIdEvent = logs.find(({ address, topics }) => address == this.axelar.target && topics[0] == this.axelar.interface.getEvent('CommandIdPending').topicHash);
      const [ commandId ] = this.axelar.interface.decodeEventLog('CommandIdPending', commandIdEvent.data, commandIdEvent.topics);

      await expect(this.receiver.executeMessage(
        this.dstGateway,
        commandId, // bytes32 is already self-encoded
        this.CAIP2,
        getAddress(this.sender),
        payload,
        attributes,
      ))
        .to.emit(this.axelar, 'ContractCallExecuted').withArgs(commandId)
        .to.emit(this.receiver, 'MessageReceived').withArgs(this.dstGateway, this.CAIP2, getAddress(this.sender), payload, attributes);
    });
  });
});
