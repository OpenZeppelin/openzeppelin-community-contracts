const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

async function fixture() {
  const [owner, other] = await ethers.getSigners();
  const registry = await ethers.deployContract('$ERC3643TrustedIssuersRegistryMock', [owner]);
  const issuerA = ethers.Wallet.createRandom().address;
  const issuerB = ethers.Wallet.createRandom().address;
  return { owner, other, registry, issuerA, issuerB };
}

describe('ERC3643TrustedIssuersRegistry', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('starts with no trusted issuers', async function () {
    await expect(this.registry.getTrustedIssuers()).to.eventually.deep.equal([]);
    await expect(this.registry.isTrustedIssuer(this.issuerA)).to.eventually.be.false;
    await expect(this.registry.getTrustedIssuerClaimTopics(this.issuerA)).to.eventually.deep.equal([]);
    await expect(this.registry.getTrustedIssuersForClaimTopic(1n)).to.eventually.deep.equal([]);
  });

  describe('addTrustedIssuer', function () {
    it('registers an issuer for its claim topics', async function () {
      await expect(this.registry.connect(this.owner).addTrustedIssuer(this.issuerA, [1n, 2n]))
        .to.emit(this.registry, 'TrustedIssuerAdded')
        .withArgs(this.issuerA, [1n, 2n]);
      await this.registry.connect(this.owner).addTrustedIssuer(this.issuerB, [2n]);

      await expect(this.registry.getTrustedIssuers()).to.eventually.deep.equal([this.issuerA, this.issuerB]);
      await expect(this.registry.isTrustedIssuer(this.issuerA)).to.eventually.be.true;
      await expect(this.registry.getTrustedIssuerClaimTopics(this.issuerA)).to.eventually.deep.equal([1n, 2n]);
      await expect(this.registry.hasClaimTopic(this.issuerA, 1n)).to.eventually.be.true;
      await expect(this.registry.hasClaimTopic(this.issuerB, 1n)).to.eventually.be.false;
      await expect(this.registry.getTrustedIssuersForClaimTopic(1n)).to.eventually.deep.equal([this.issuerA]);
      await expect(this.registry.getTrustedIssuersForClaimTopic(2n)).to.eventually.deep.equal([
        this.issuerA,
        this.issuerB,
      ]);
    });

    it('stores duplicated claim topics once', async function () {
      await this.registry.connect(this.owner).addTrustedIssuer(this.issuerA, [1n, 1n]);
      await expect(this.registry.getTrustedIssuerClaimTopics(this.issuerA)).to.eventually.deep.equal([1n]);
      await expect(this.registry.getTrustedIssuersForClaimTopic(1n)).to.eventually.deep.equal([this.issuerA]);
    });

    it('reverts when the issuer is already registered', async function () {
      await this.registry.connect(this.owner).addTrustedIssuer(this.issuerA, [1n]);
      await expect(this.registry.connect(this.owner).addTrustedIssuer(this.issuerA, [2n]))
        .to.be.revertedWithCustomError(this.registry, 'ERC3643TrustedIssuerAlreadyRegistered')
        .withArgs(this.issuerA);
    });

    it('reverts when the issuer is the zero address', async function () {
      await expect(this.registry.connect(this.owner).addTrustedIssuer(ethers.ZeroAddress, [1n]))
        .to.be.revertedWithCustomError(this.registry, 'ERC3643InvalidTrustedIssuer')
        .withArgs(ethers.ZeroAddress);
    });

    it('reverts when no claim topic is given', async function () {
      await expect(this.registry.connect(this.owner).addTrustedIssuer(this.issuerA, []))
        .to.be.revertedWithCustomError(this.registry, 'ERC3643EmptyClaimTopics')
        .withArgs(this.issuerA);
    });

    it('reverts when the caller is not authorized', async function () {
      await expect(this.registry.connect(this.other).addTrustedIssuer(this.issuerA, [1n]))
        .to.be.revertedWithCustomError(this.registry, 'OwnableUnauthorizedAccount')
        .withArgs(this.other);
    });
  });

  describe('removeTrustedIssuer', function () {
    beforeEach(async function () {
      await this.registry.connect(this.owner).addTrustedIssuer(this.issuerA, [1n, 2n]);
      await this.registry.connect(this.owner).addTrustedIssuer(this.issuerB, [2n]);
    });

    it('removes the issuer and its claim topics', async function () {
      await expect(this.registry.connect(this.owner).removeTrustedIssuer(this.issuerA))
        .to.emit(this.registry, 'TrustedIssuerRemoved')
        .withArgs(this.issuerA);

      await expect(this.registry.getTrustedIssuers()).to.eventually.deep.equal([this.issuerB]);
      await expect(this.registry.isTrustedIssuer(this.issuerA)).to.eventually.be.false;
      await expect(this.registry.getTrustedIssuerClaimTopics(this.issuerA)).to.eventually.deep.equal([]);
      await expect(this.registry.hasClaimTopic(this.issuerA, 1n)).to.eventually.be.false;
      await expect(this.registry.getTrustedIssuersForClaimTopic(1n)).to.eventually.deep.equal([]);
      await expect(this.registry.getTrustedIssuersForClaimTopic(2n)).to.eventually.deep.equal([this.issuerB]);
    });

    it('allows registering the issuer again', async function () {
      await this.registry.connect(this.owner).removeTrustedIssuer(this.issuerA);
      await this.registry.connect(this.owner).addTrustedIssuer(this.issuerA, [3n]);
      await expect(this.registry.getTrustedIssuerClaimTopics(this.issuerA)).to.eventually.deep.equal([3n]);
      await expect(this.registry.getTrustedIssuersForClaimTopic(1n)).to.eventually.deep.equal([]);
    });

    it('reverts when the issuer is not registered', async function () {
      await expect(this.registry.connect(this.owner).removeTrustedIssuer(this.other))
        .to.be.revertedWithCustomError(this.registry, 'ERC3643TrustedIssuerNotRegistered')
        .withArgs(this.other);
    });

    it('reverts when the caller is not authorized', async function () {
      await expect(this.registry.connect(this.other).removeTrustedIssuer(this.issuerA))
        .to.be.revertedWithCustomError(this.registry, 'OwnableUnauthorizedAccount')
        .withArgs(this.other);
    });
  });

  describe('updateIssuerClaimTopics', function () {
    beforeEach(async function () {
      await this.registry.connect(this.owner).addTrustedIssuer(this.issuerA, [1n, 2n]);
    });

    it('replaces the claim topics of the issuer', async function () {
      await expect(this.registry.connect(this.owner).updateIssuerClaimTopics(this.issuerA, [2n, 3n]))
        .to.emit(this.registry, 'ClaimTopicsUpdated')
        .withArgs(this.issuerA, [2n, 3n]);

      await expect(this.registry.getTrustedIssuerClaimTopics(this.issuerA)).to.eventually.deep.equal([2n, 3n]);
      await expect(this.registry.getTrustedIssuersForClaimTopic(1n)).to.eventually.deep.equal([]);
      await expect(this.registry.getTrustedIssuersForClaimTopic(2n)).to.eventually.deep.equal([this.issuerA]);
      await expect(this.registry.getTrustedIssuersForClaimTopic(3n)).to.eventually.deep.equal([this.issuerA]);
    });

    it('reverts when the issuer is not registered', async function () {
      await expect(this.registry.connect(this.owner).updateIssuerClaimTopics(this.issuerB, [1n]))
        .to.be.revertedWithCustomError(this.registry, 'ERC3643TrustedIssuerNotRegistered')
        .withArgs(this.issuerB);
    });

    it('reverts when no claim topic is given', async function () {
      await expect(this.registry.connect(this.owner).updateIssuerClaimTopics(this.issuerA, []))
        .to.be.revertedWithCustomError(this.registry, 'ERC3643EmptyClaimTopics')
        .withArgs(this.issuerA);
    });

    it('reverts when the caller is not authorized', async function () {
      await expect(this.registry.connect(this.other).updateIssuerClaimTopics(this.issuerA, [1n]))
        .to.be.revertedWithCustomError(this.registry, 'OwnableUnauthorizedAccount')
        .withArgs(this.other);
    });
  });

  describe('internal functions', function () {
    it('_addTrustedIssuer returns false without emitting for a registered issuer', async function () {
      await this.registry.$_addTrustedIssuer(this.issuerA, [1n]);
      await expect(this.registry.$_addTrustedIssuer.staticCall(this.issuerA, [2n])).to.eventually.be.false;
      await expect(this.registry.$_addTrustedIssuer(this.issuerA, [2n])).to.not.emit(
        this.registry,
        'TrustedIssuerAdded',
      );
      await expect(this.registry.getTrustedIssuerClaimTopics(this.issuerA)).to.eventually.deep.equal([1n]);
    });

    it('_removeTrustedIssuer returns false for an unregistered issuer', async function () {
      await expect(this.registry.$_removeTrustedIssuer.staticCall(this.issuerA)).to.eventually.be.false;
    });

    it('_updateIssuerClaimTopics returns false for an unregistered issuer', async function () {
      await expect(this.registry.$_updateIssuerClaimTopics.staticCall(this.issuerA, [1n])).to.eventually.be.false;
    });
  });
});
