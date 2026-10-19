const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

async function fixture() {
  const [owner, registry, other, account] = await ethers.getSigners();
  const storage = await ethers.deployContract('$ERC3643IdentityRegistryStorageMock', [owner]);
  await storage.connect(owner).bindIdentityRegistry(registry);
  const identity = ethers.Wallet.createRandom().address;
  const otherIdentity = ethers.Wallet.createRandom().address;
  return { owner, registry, other, account, storage, identity, otherIdentity };
}

describe('ERC3643IdentityRegistryStorage', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('identity registry binding', function () {
    it('binds an identity registry', async function () {
      await expect(this.storage.connect(this.owner).bindIdentityRegistry(this.other))
        .to.emit(this.storage, 'IdentityRegistryBound')
        .withArgs(this.other);
      await expect(this.storage.linkedIdentityRegistries()).to.eventually.deep.equal([
        this.registry.address,
        this.other.address,
      ]);
    });

    it('unbinds an identity registry', async function () {
      await expect(this.storage.connect(this.owner).unbindIdentityRegistry(this.registry))
        .to.emit(this.storage, 'IdentityRegistryUnbound')
        .withArgs(this.registry);
      await expect(this.storage.linkedIdentityRegistries()).to.eventually.deep.equal([]);
    });

    it('reverts when binding a bound registry', async function () {
      await expect(this.storage.connect(this.owner).bindIdentityRegistry(this.registry))
        .to.be.revertedWithCustomError(this.storage, 'ERC3643IdentityRegistryAlreadyBound')
        .withArgs(this.registry);
    });

    it('reverts when binding the zero address', async function () {
      await expect(this.storage.connect(this.owner).bindIdentityRegistry(ethers.ZeroAddress))
        .to.be.revertedWithCustomError(this.storage, 'ERC3643InvalidIdentityRegistry')
        .withArgs(ethers.ZeroAddress);
    });

    it('reverts when unbinding an unbound registry', async function () {
      await expect(this.storage.connect(this.owner).unbindIdentityRegistry(this.other))
        .to.be.revertedWithCustomError(this.storage, 'ERC3643IdentityRegistryNotBound')
        .withArgs(this.other);
    });

    it('reverts when the caller is not authorized', async function () {
      await expect(this.storage.connect(this.other).bindIdentityRegistry(this.other))
        .to.be.revertedWithCustomError(this.storage, 'OwnableUnauthorizedAccount')
        .withArgs(this.other);
      await expect(this.storage.connect(this.other).unbindIdentityRegistry(this.registry))
        .to.be.revertedWithCustomError(this.storage, 'OwnableUnauthorizedAccount')
        .withArgs(this.other);
    });

    it('stops accepting writes from an unbound registry', async function () {
      await this.storage.connect(this.owner).unbindIdentityRegistry(this.registry);
      await expect(this.storage.connect(this.registry).addIdentityToStorage(this.account, this.identity, 42n))
        .to.be.revertedWithCustomError(this.storage, 'ERC3643UnauthorizedIdentityRegistry')
        .withArgs(this.registry);
    });
  });

  describe('addIdentityToStorage', function () {
    it('stores an identity and a country', async function () {
      await expect(this.storage.connect(this.registry).addIdentityToStorage(this.account, this.identity, 42n))
        .to.emit(this.storage, 'IdentityStored')
        .withArgs(this.account, this.identity);
      await expect(this.storage.storedIdentity(this.account)).to.eventually.equal(this.identity);
      await expect(this.storage.storedInvestorCountry(this.account)).to.eventually.equal(42n);
    });

    it('reverts when the account already has an identity', async function () {
      await this.storage.connect(this.registry).addIdentityToStorage(this.account, this.identity, 42n);
      await expect(this.storage.connect(this.registry).addIdentityToStorage(this.account, this.otherIdentity, 1n))
        .to.be.revertedWithCustomError(this.storage, 'ERC3643IdentityAlreadyStored')
        .withArgs(this.account);
    });

    it('reverts when the account is the zero address', async function () {
      await expect(this.storage.connect(this.registry).addIdentityToStorage(ethers.ZeroAddress, this.identity, 42n))
        .to.be.revertedWithCustomError(this.storage, 'ERC3643InvalidAccount')
        .withArgs(ethers.ZeroAddress);
    });

    it('reverts when the identity is the zero address', async function () {
      await expect(this.storage.connect(this.registry).addIdentityToStorage(this.account, ethers.ZeroAddress, 42n))
        .to.be.revertedWithCustomError(this.storage, 'ERC3643InvalidIdentity')
        .withArgs(ethers.ZeroAddress);
    });

    it('reverts when the caller is not a bound registry', async function () {
      await expect(this.storage.connect(this.owner).addIdentityToStorage(this.account, this.identity, 42n))
        .to.be.revertedWithCustomError(this.storage, 'ERC3643UnauthorizedIdentityRegistry')
        .withArgs(this.owner);
    });
  });

  describe('with a stored identity', function () {
    beforeEach(async function () {
      await this.storage.connect(this.registry).addIdentityToStorage(this.account, this.identity, 42n);
    });

    it('removes the identity and the country', async function () {
      await expect(this.storage.connect(this.registry).removeIdentityFromStorage(this.account))
        .to.emit(this.storage, 'IdentityUnstored')
        .withArgs(this.account, this.identity);
      await expect(this.storage.storedIdentity(this.account)).to.eventually.equal(ethers.ZeroAddress);
      await expect(this.storage.storedInvestorCountry(this.account)).to.eventually.equal(0n);
    });

    it('modifies the country', async function () {
      await expect(this.storage.connect(this.registry).modifyStoredInvestorCountry(this.account, 7n))
        .to.emit(this.storage, 'CountryModified')
        .withArgs(this.account, 7n);
      await expect(this.storage.storedInvestorCountry(this.account)).to.eventually.equal(7n);
      await expect(this.storage.storedIdentity(this.account)).to.eventually.equal(this.identity);
    });

    it('modifies the identity', async function () {
      await expect(this.storage.connect(this.registry).modifyStoredIdentity(this.account, this.otherIdentity))
        .to.emit(this.storage, 'IdentityModified')
        .withArgs(this.identity, this.otherIdentity);
      await expect(this.storage.storedIdentity(this.account)).to.eventually.equal(this.otherIdentity);
      await expect(this.storage.storedInvestorCountry(this.account)).to.eventually.equal(42n);
    });

    it('reverts when modifying the identity to the zero address', async function () {
      await expect(this.storage.connect(this.registry).modifyStoredIdentity(this.account, ethers.ZeroAddress))
        .to.be.revertedWithCustomError(this.storage, 'ERC3643InvalidIdentity')
        .withArgs(ethers.ZeroAddress);
    });

    it('reverts when the caller is not a bound registry', async function () {
      for (const call of [
        this.storage.connect(this.other).removeIdentityFromStorage(this.account),
        this.storage.connect(this.other).modifyStoredInvestorCountry(this.account, 7n),
        this.storage.connect(this.other).modifyStoredIdentity(this.account, this.otherIdentity),
      ]) {
        await expect(call)
          .to.be.revertedWithCustomError(this.storage, 'ERC3643UnauthorizedIdentityRegistry')
          .withArgs(this.other);
      }
    });
  });

  describe('without a stored identity', function () {
    it('reverts on removal and modifications', async function () {
      for (const call of [
        this.storage.connect(this.registry).removeIdentityFromStorage(this.account),
        this.storage.connect(this.registry).modifyStoredInvestorCountry(this.account, 7n),
        this.storage.connect(this.registry).modifyStoredIdentity(this.account, this.otherIdentity),
      ]) {
        await expect(call)
          .to.be.revertedWithCustomError(this.storage, 'ERC3643IdentityNotStored')
          .withArgs(this.account);
      }
    });

    it('internal functions return false', async function () {
      await expect(this.storage.$_removeIdentityFromStorage.staticCall(this.account)).to.eventually.be.false;
      await expect(this.storage.$_modifyStoredInvestorCountry.staticCall(this.account, 7n)).to.eventually.be.false;
      await expect(this.storage.$_modifyStoredIdentity.staticCall(this.account, this.otherIdentity)).to.eventually.be
        .false;
      await expect(this.storage.$_unbindIdentityRegistry.staticCall(this.other)).to.eventually.be.false;
    });
  });
});
