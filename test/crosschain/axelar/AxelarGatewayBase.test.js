const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { toBeHex, hexlify } = require('ethers');

async function fixture() {
  const [owner, other] = await ethers.getSigners();

  const localGateway = await ethers.deployContract('AxelarGatewayMock');
  const mock = await ethers.deployContract('$AxelarGatewayBase', [owner, localGateway]);
  return { owner, other, mock };
}

describe('AxelarGatewayBase', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('fromCAIP2', function () {
    it('returns empty string if the chain is not supported', async function () {
      expect(await this.mock['fromCAIP2(string)']('eip155:11155111')).to.equal('');
    });

    it('returns the chain name if the chain is supported', async function () {
      await this.mock.connect(this.owner).registerCAIP2Equivalence('eip155:1', 'Ethereum');
      expect(await this.mock['fromCAIP2(string)']('eip155:1')).to.equal('Ethereum');
    });
  });

  describe('getRemoteGateway', function () {
    it('returns empty string if there is no remote gateway', async function () {
      expect(await this.mock.getRemoteGateway('unknown:unknown')).to.equal('');
    });

    it('returns the remote gateway if it exists', async function () {
      await this.mock.connect(this.owner).registerRemoteGateway('eip155:1', this.other.address);
      expect(await this.mock.getRemoteGateway('eip155:1')).to.equal(this.other.address);
    });
  });

  describe('registerCAIP2Equivalence', function () {
    it('emits an event', async function () {
      await expect(this.mock.connect(this.owner).registerCAIP2Equivalence('eip155:1', 'Ethereum'))
        .to.emit(this.mock, 'RegisteredCAIP2Equivalence')
        .withArgs('eip155:1', 'Ethereum');
    });

    it('reverts if the chain is already registered', async function () {
      await this.mock.connect(this.owner).registerCAIP2Equivalence('eip155:1', 'Ethereum');
      await expect(this.mock.connect(this.owner).registerCAIP2Equivalence('eip155:1', 'Ethereum')).to.be.reverted;
    });
  });

  describe('registerRemoteGateway', function () {
    it('emits an event', async function () {
      await expect(this.mock.connect(this.owner).registerRemoteGateway('eip155:1', this.other.address))
        .to.emit(this.mock, 'RegisteredRemoteGateway')
        .withArgs('eip155:1', this.other.address);
    });

    it('reverts if the chain is already registered', async function () {
      await this.mock.connect(this.owner).registerRemoteGateway('eip155:1', this.other.address); // register once
      await expect(this.mock.connect(this.owner).registerRemoteGateway('eip155:1', this.other.address)).to.be
        .reverted;
    });
  });
});
