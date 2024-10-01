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

  const axelar     = await ethers.deployContract('$AxelarGatewayMock');
  const srcGateway = await ethers.deployContract('$AxelarGatewaySource', [ owner, axelar ]);
  const dstGateway = await ethers.deployContract('$AxelarGatewayDestination', [ owner, axelar, axelar ]);
  const receiver   = await ethers.deployContract('$GatewayReceiverMock', [ dstGateway ]);

  await srcGateway.registerChainEquivalence(CAIP2, 'local');
  await dstGateway.registerChainEquivalence(CAIP2, 'local');
  await srcGateway.registerRemoteGateway(CAIP2, getAddress(dstGateway));
  await dstGateway.registerRemoteGateway(CAIP2, getAddress(srcGateway));

  return { owner, sender, accounts, CAIP2, asCAIP10, axelar, srcGateway, dstGateway, receiver };
}

describe('AxelarGateway', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('initial setup', async function () {
    expect(await this.srcGateway.localGateway()).to.equal(this.axelar);
    expect(await this.srcGateway.getEquivalentChain(this.CAIP2)).to.equal('local');
    expect(await this.srcGateway.getRemoteGateway(this.CAIP2)).to.equal(getAddress(this.dstGateway));

    expect(await this.dstGateway.localGateway()).to.equal(this.axelar);
    expect(await this.dstGateway.getEquivalentChain(this.CAIP2)).to.equal('local');
    expect(await this.dstGateway.getRemoteGateway(this.CAIP2)).to.equal(getAddress(this.srcGateway));
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

      const tx = await this.srcGateway.connect(this.sender).sendMessage(this.CAIP2, getAddress(this.receiver), payload, attributes);
      await expect(tx)
        .to.emit(this.srcGateway, 'MessageCreated').withArgs(ethers.ZeroHash, srcCAIP10, dstCAIP10, payload, attributes)
        .to.emit(this.axelar, 'ContractCall').withArgs(this.srcGateway, 'local', getAddress(this.dstGateway), ethers.keccak256(package), package)
        .to.emit(this.axelar, 'ContractCallExecuted').withArgs(anyValue)
        .to.emit(this.receiver, 'MessageReceived').withArgs(anyValue, this.CAIP2, getAddress(this.sender), payload, attributes);
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
        .to.emit(this.srcGateway, 'MessageCreated').withArgs(ethers.ZeroHash, srcCAIP10, dstCAIP10, payload, attributes)
        .to.emit(this.axelar, 'ContractCall').withArgs(this.srcGateway, 'local', getAddress(this.dstGateway), ethers.keccak256(package), package)
        .to.emit(this.axelar, 'CommandIdPending').withArgs(anyValue, 'local', getAddress(this.dstGateway), package);

      const { logs } = await tx.wait();
      const commandIdEvent = logs.find(({ address, topics }) => address == this.axelar.target && topics[0] == this.axelar.interface.getEvent('CommandIdPending').topicHash);
      const [ commandId ] = this.axelar.interface.decodeEventLog('CommandIdPending', commandIdEvent.data, commandIdEvent.topics);

      await expect(this.receiver.receiveMessage(
        this.dstGateway,
        commandId, // bytes32 is already self-encoded
        this.CAIP2,
        getAddress(this.sender),
        payload,
        attributes,
      ))
        .to.emit(this.axelar, 'ContractCallExecuted').withArgs(commandId)
        .to.emit(this.receiver, 'MessageReceived').withArgs(commandId, this.CAIP2, getAddress(this.sender), payload, attributes);
    });
  });
});
