const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const getSelectors = iface =>
  []
    .concat(
      iface.fragments.filter(({ type }) => type == 'function').map(({ selector }) => selector),
      iface.receive && '0x00000000',
      iface.fallback && '0xFFFFFFFF',
    )
    .filter(Boolean);

async function fixture() {
  const [admin, other] = await ethers.getSigners();

  const modules = {
    diamondCut: await ethers.deployContract('DiamondCutFacet'),
    diamondLoupe: await ethers.deployContract('DiamondLoupeFacet'),
    ownership: await ethers.deployContract('DispatchOwnershipModule'),
    update: await ethers.deployContract('DispatchUpdateModule'),
    mock: await ethers.deployContract('DispatchModuleMock'),
  };
  const proxy = await ethers.deployContract('DispatchProxy', [modules.update, admin]);
  const proxyAsUpdate = modules.update.attach(proxy.target);

  return { admin, other, modules, proxy, proxyAsUpdate };
}

describe('DispatchProxy', async function () {
  beforeEach('deploying', async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('missing implementation', async function () {
    await expect(this.other.sendTransaction({ to: this.proxy })).to.be.revertedWithCustomError(
      this.proxy,
      'DispatchProxyMissingImplementation',
    );
  });

  describe('dispatch table update', function () {
    it('authorized', async function () {
      const modules = [this.modules.diamondCut, this.modules.diamondLoupe, this.modules.ownership];

      const tx = this.proxyAsUpdate
        .connect(this.admin)
        .updateDispatchTable(modules.map(module => [module, getSelectors(module.interface)]));
      for (const module of modules) {
        for (const selector of getSelectors(module.interface)) {
          await expect(tx).to.emit(this.proxyAsUpdate, 'VMTUpdate').withArgs(selector, ethers.ZeroAddress, module);
        }
      }
    });

    it('unauthorized', async function () {
      const modules = [this.modules.diamondCut, this.modules.diamondLoupe, this.modules.ownership];

      await expect(
        this.proxyAsUpdate
          .connect(this.other)
          .updateDispatchTable(modules.map(module => [module, getSelectors(module.interface)])),
      )
        .to.be.revertedWithCustomError(this.proxyAsUpdate, 'OwnableUnauthorizedAccount')
        .withArgs(this.other);
    });

    it('empty update', async function () {
      const tx = await this.proxyAsUpdate.connect(this.admin).updateDispatchTable([]);
      const receipt = await tx.wait();

      expect(receipt.logs.length).to.be.equal(0);
    });

    it('receive', async function () {
      const receiver = await ethers.deployContract('EtherReceiverMock');
      await this.proxyAsUpdate.connect(this.admin).updateDispatchTable([[receiver, getSelectors(receiver.interface)]]);

      // does not accept eth
      await expect(this.other.sendTransaction({ to: this.proxy, value: 1n })).to.be.revertedWithoutReason();

      // set accept eth
      await receiver.attach(this.proxy.target).setAcceptEther(true);

      // accept eth
      await expect(this.other.sendTransaction({ to: this.proxy, value: 1n })).to.not.be.reverted;
    });

    it('fallback', async function () {
      const receiver = await ethers.deployContract('EtherReceiverMock');
      await this.proxyAsUpdate.connect(this.admin).updateDispatchTable([[receiver, ['0xffffffff']]]);

      // does not accept eth
      await expect(this.other.sendTransaction({ to: this.proxy, value: 1n })).to.be.revertedWithoutReason();

      // set accept eth
      await receiver.attach(this.proxy.target).setAcceptEther(true);

      // accept eth
      await expect(this.other.sendTransaction({ to: this.proxy, value: 1n })).to.not.be.reverted;
    });
  });

  describe('with ownership module', function () {
    beforeEach(async function () {
      await this.proxyAsUpdate
        .connect(this.admin)
        .updateDispatchTable([[this.modules.ownership, getSelectors(this.modules.ownership.interface)]]);
      this.proxyAsOwnership = this.modules.ownership.attach(this.proxy.target);
    });

    it('has an owner', async function () {
      await expect(this.proxyAsOwnership.owner()).to.eventually.equal(this.admin);
    });

    describe('transfer ownership', function () {
      it('changes owner after transfer', async function () {
        await expect(this.proxyAsOwnership.connect(this.admin).transferOwnership(this.other))
          .to.emit(this.proxyAsOwnership, 'OwnershipTransferred')
          .withArgs(this.admin, this.other);

        await expect(this.proxyAsOwnership.owner()).to.eventually.equal(this.other);
      });

      it('prevents non-owners from transferring', async function () {
        await expect(this.proxyAsOwnership.connect(this.other).transferOwnership(this.other))
          .to.be.revertedWithCustomError(this.proxyAsOwnership, 'OwnableUnauthorizedAccount')
          .withArgs(this.other);
      });

      it('guards ownership against stuck state', async function () {
        await expect(this.proxyAsOwnership.connect(this.admin).transferOwnership(ethers.ZeroAddress))
          .to.be.revertedWithCustomError(this.proxyAsOwnership, 'OwnableInvalidOwner')
          .withArgs(ethers.ZeroAddress);
      });
    });

    describe('renounce ownership', function () {
      it('loses owner after renouncement', async function () {
        await expect(this.proxyAsOwnership.connect(this.admin).renounceOwnership())
          .to.emit(this.proxyAsOwnership, 'OwnershipTransferred')
          .withArgs(this.admin, ethers.ZeroAddress);

        await expect(this.proxyAsOwnership.owner()).to.eventually.equal(ethers.ZeroAddress);
      });

      it('prevents non-owners from renouncement', async function () {
        await expect(this.proxyAsOwnership.connect(this.other).renounceOwnership())
          .to.be.revertedWithCustomError(this.proxyAsOwnership, 'OwnableUnauthorizedAccount')
          .withArgs(this.other);
      });
    });
  });
});
