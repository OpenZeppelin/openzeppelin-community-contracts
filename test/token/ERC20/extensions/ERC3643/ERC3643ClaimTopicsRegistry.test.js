const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

async function fixture() {
  const [owner, other] = await ethers.getSigners();
  const registry = await ethers.deployContract('$ERC3643ClaimTopicsRegistryMock', [owner]);
  return { owner, other, registry };
}

describe('ERC3643ClaimTopicsRegistry', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('starts with no claim topics', async function () {
    await expect(this.registry.getClaimTopics()).to.eventually.deep.equal([]);
  });

  describe('addClaimTopic', function () {
    it('adds a claim topic', async function () {
      await expect(this.registry.connect(this.owner).addClaimTopic(1n))
        .to.emit(this.registry, 'ClaimTopicAdded')
        .withArgs(1n);
      await this.registry.connect(this.owner).addClaimTopic(2n);
      await expect(this.registry.getClaimTopics()).to.eventually.deep.equal([1n, 2n]);
    });

    it('reverts when the claim topic is already registered', async function () {
      await this.registry.connect(this.owner).addClaimTopic(1n);
      await expect(this.registry.connect(this.owner).addClaimTopic(1n))
        .to.be.revertedWithCustomError(this.registry, 'ERC3643ClaimTopicAlreadyRegistered')
        .withArgs(1n);
    });

    it('reverts when the caller is not authorized', async function () {
      await expect(this.registry.connect(this.other).addClaimTopic(1n))
        .to.be.revertedWithCustomError(this.registry, 'OwnableUnauthorizedAccount')
        .withArgs(this.other);
    });
  });

  describe('removeClaimTopic', function () {
    beforeEach(async function () {
      await this.registry.connect(this.owner).addClaimTopic(1n);
      await this.registry.connect(this.owner).addClaimTopic(2n);
    });

    it('removes a claim topic', async function () {
      await expect(this.registry.connect(this.owner).removeClaimTopic(1n))
        .to.emit(this.registry, 'ClaimTopicRemoved')
        .withArgs(1n);
      await expect(this.registry.getClaimTopics()).to.eventually.deep.equal([2n]);
    });

    it('reverts when the claim topic is not registered', async function () {
      await expect(this.registry.connect(this.owner).removeClaimTopic(3n))
        .to.be.revertedWithCustomError(this.registry, 'ERC3643ClaimTopicNotRegistered')
        .withArgs(3n);
    });

    it('reverts when the caller is not authorized', async function () {
      await expect(this.registry.connect(this.other).removeClaimTopic(1n))
        .to.be.revertedWithCustomError(this.registry, 'OwnableUnauthorizedAccount')
        .withArgs(this.other);
    });
  });

  describe('internal functions', function () {
    it('_addClaimTopic returns false without emitting for a registered topic', async function () {
      await this.registry.$_addClaimTopic(1n);
      await expect(this.registry.$_addClaimTopic.staticCall(1n)).to.eventually.be.false;
      await expect(this.registry.$_addClaimTopic(1n)).to.not.emit(this.registry, 'ClaimTopicAdded');
    });

    it('_removeClaimTopic returns false without emitting for an unregistered topic', async function () {
      await expect(this.registry.$_removeClaimTopic.staticCall(1n)).to.eventually.be.false;
      await expect(this.registry.$_removeClaimTopic(1n)).to.not.emit(this.registry, 'ClaimTopicRemoved');
    });
  });
});
