const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const Answer = { Valid: 0n, Invalid: 1n, Revert: 2n, NonBoolean: 3n, Oversized: 4n };

const KYC = 1n;
const AML = 2n;
const signature = '0x1234';
const data = '0xabcd';

async function fixture() {
  const [owner, other, account, otherAccount] = await ethers.getSigners();

  const storage = await ethers.deployContract('$ERC3643IdentityRegistryStorageMock', [owner]);
  const issuers = await ethers.deployContract('$ERC3643TrustedIssuersRegistryMock', [owner]);
  const topics = await ethers.deployContract('$ERC3643ClaimTopicsRegistryMock', [owner]);
  const registry = await ethers.deployContract('$ERC3643IdentityRegistryMock', [storage, issuers, topics, owner]);
  await storage.connect(owner).bindIdentityRegistry(registry);

  const identity = await ethers.deployContract('ERC735IdentityMock');
  const otherIdentity = await ethers.deployContract('ERC735IdentityMock');
  const issuer = await ethers.deployContract('ERC735ClaimIssuerMock');
  const otherIssuer = await ethers.deployContract('ERC735ClaimIssuerMock');

  return {
    owner,
    other,
    account,
    otherAccount,
    storage,
    issuers,
    topics,
    registry,
    identity,
    otherIdentity,
    issuer,
    otherIssuer,
  };
}

describe('ERC3643IdentityRegistry', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('construction', function () {
    it('sets the identity storage and the registries', async function () {
      await expect(this.registry.identityStorage()).to.eventually.equal(this.storage);
      await expect(this.registry.issuersRegistry()).to.eventually.equal(this.issuers);
      await expect(this.registry.topicsRegistry()).to.eventually.equal(this.topics);
    });

    it('emits an event for each of them', async function () {
      const registry = await ethers.deployContract('$ERC3643IdentityRegistryMock', [
        this.storage,
        this.issuers,
        this.topics,
        this.owner,
      ]);
      const tx = registry.deploymentTransaction();
      await expect(tx).to.emit(registry, 'IdentityStorageSet').withArgs(this.storage);
      await expect(tx).to.emit(registry, 'TrustedIssuersRegistrySet').withArgs(this.issuers);
      await expect(tx).to.emit(registry, 'ClaimTopicsRegistrySet').withArgs(this.topics);
    });

    for (const [index, error] of [
      [0, 'ERC3643MissingIdentityRegistryStorage'],
      [1, 'ERC3643MissingTrustedIssuersRegistry'],
      [2, 'ERC3643MissingClaimTopicsRegistry'],
    ]) {
      it(`reverts with ${error}`, async function () {
        const args = [this.storage, this.issuers, this.topics, this.owner];
        args[index] = ethers.ZeroAddress;
        const factory = await ethers.getContractFactory('$ERC3643IdentityRegistryMock');
        await expect(factory.deploy(...args)).to.be.revertedWithCustomError(this.registry, error);
      });
    }
  });

  describe('registry setters', function () {
    for (const [fn, event, error] of [
      ['setIdentityRegistryStorage', 'IdentityStorageSet', 'ERC3643MissingIdentityRegistryStorage'],
      ['setTrustedIssuersRegistry', 'TrustedIssuersRegistrySet', 'ERC3643MissingTrustedIssuersRegistry'],
      ['setClaimTopicsRegistry', 'ClaimTopicsRegistrySet', 'ERC3643MissingClaimTopicsRegistry'],
    ]) {
      describe(fn, function () {
        it('replaces the registry', async function () {
          await expect(this.registry.connect(this.owner)[fn](this.other))
            .to.emit(this.registry, event)
            .withArgs(this.other);
        });

        it('reverts with the zero address', async function () {
          await expect(this.registry.connect(this.owner)[fn](ethers.ZeroAddress)).to.be.revertedWithCustomError(
            this.registry,
            error,
          );
        });

        it('reverts when the caller is not authorized', async function () {
          await expect(this.registry.connect(this.other)[fn](this.other))
            .to.be.revertedWithCustomError(this.registry, 'OwnableUnauthorizedAccount')
            .withArgs(this.other);
        });
      });
    }

    it('reads identities from the new storage', async function () {
      await this.registry.connect(this.owner).registerIdentity(this.account, this.identity, 42n);
      const storage = await ethers.deployContract('$ERC3643IdentityRegistryStorageMock', [this.owner]);
      await this.registry.connect(this.owner).setIdentityRegistryStorage(storage);
      await expect(this.registry.contains(this.account)).to.eventually.be.false;
    });
  });

  describe('identity management', function () {
    it('registers an identity', async function () {
      await expect(this.registry.connect(this.owner).registerIdentity(this.account, this.identity, 42n))
        .to.emit(this.registry, 'IdentityRegistered')
        .withArgs(this.account, this.identity)
        .to.emit(this.storage, 'IdentityStored')
        .withArgs(this.account, this.identity);
      await expect(this.registry.contains(this.account)).to.eventually.be.true;
      await expect(this.registry.identity(this.account)).to.eventually.equal(this.identity);
      await expect(this.registry.investorCountry(this.account)).to.eventually.equal(42n);
    });

    it('reverts when registering a registered account', async function () {
      await this.registry.connect(this.owner).registerIdentity(this.account, this.identity, 42n);
      await expect(this.registry.connect(this.owner).registerIdentity(this.account, this.otherIdentity, 1n))
        .to.be.revertedWithCustomError(this.storage, 'ERC3643IdentityAlreadyStored')
        .withArgs(this.account);
    });

    it('reverts when the storage did not bind the registry', async function () {
      await this.storage.connect(this.owner).unbindIdentityRegistry(this.registry);
      await expect(this.registry.connect(this.owner).registerIdentity(this.account, this.identity, 42n))
        .to.be.revertedWithCustomError(this.storage, 'ERC3643UnauthorizedIdentityRegistry')
        .withArgs(this.registry);
    });

    it('registers identities in batch', async function () {
      await this.registry
        .connect(this.owner)
        .batchRegisterIdentity([this.account, this.otherAccount], [this.identity, this.otherIdentity], [42n, 7n]);
      await expect(this.registry.identity(this.account)).to.eventually.equal(this.identity);
      await expect(this.registry.identity(this.otherAccount)).to.eventually.equal(this.otherIdentity);
      await expect(this.registry.investorCountry(this.otherAccount)).to.eventually.equal(7n);
    });

    for (const [identities, countries] of [
      [1, 2],
      [2, 1],
    ]) {
      it(`reverts a batch with arrays of different lengths (2, ${identities}, ${countries})`, async function () {
        await expect(
          this.registry
            .connect(this.owner)
            .batchRegisterIdentity(
              [this.account, this.otherAccount],
              [this.identity, this.otherIdentity].slice(0, identities),
              [42n, 7n].slice(0, countries),
            ),
        ).to.be.revertedWithCustomError(this.registry, 'ERC3643InvalidArrayLength');
      });
    }

    describe('with a registered identity', function () {
      beforeEach(async function () {
        await this.registry.connect(this.owner).registerIdentity(this.account, this.identity, 42n);
      });

      it('deletes the identity', async function () {
        await expect(this.registry.connect(this.owner).deleteIdentity(this.account))
          .to.emit(this.registry, 'IdentityRemoved')
          .withArgs(this.account, this.identity);
        await expect(this.registry.contains(this.account)).to.eventually.be.false;
        await expect(this.registry.investorCountry(this.account)).to.eventually.equal(0n);
      });

      it('updates the country', async function () {
        await expect(this.registry.connect(this.owner).updateCountry(this.account, 7n))
          .to.emit(this.registry, 'CountryUpdated')
          .withArgs(this.account, 7n);
        await expect(this.registry.investorCountry(this.account)).to.eventually.equal(7n);
      });

      it('updates the identity', async function () {
        await expect(this.registry.connect(this.owner).updateIdentity(this.account, this.otherIdentity))
          .to.emit(this.registry, 'IdentityUpdated')
          .withArgs(this.identity, this.otherIdentity);
        await expect(this.registry.identity(this.account)).to.eventually.equal(this.otherIdentity);
      });
    });

    it('reverts when updating an unregistered account', async function () {
      for (const call of [
        this.registry.connect(this.owner).deleteIdentity(this.account),
        this.registry.connect(this.owner).updateCountry(this.account, 7n),
        this.registry.connect(this.owner).updateIdentity(this.account, this.otherIdentity),
      ]) {
        await expect(call)
          .to.be.revertedWithCustomError(this.storage, 'ERC3643IdentityNotStored')
          .withArgs(this.account);
      }
    });

    it('reverts when the caller is not authorized', async function () {
      for (const call of [
        this.registry.connect(this.other).registerIdentity(this.account, this.identity, 42n),
        this.registry.connect(this.other).batchRegisterIdentity([], [], []),
        this.registry.connect(this.other).deleteIdentity(this.account),
        this.registry.connect(this.other).updateCountry(this.account, 7n),
        this.registry.connect(this.other).updateIdentity(this.account, this.otherIdentity),
      ]) {
        await expect(call)
          .to.be.revertedWithCustomError(this.registry, 'OwnableUnauthorizedAccount')
          .withArgs(this.other);
      }
    });
  });

  describe('isVerified', function () {
    it('returns false for an unregistered account', async function () {
      await expect(this.registry.isVerified(this.account)).to.eventually.be.false;
    });

    describe('with a registered identity', function () {
      beforeEach(async function () {
        await this.registry.connect(this.owner).registerIdentity(this.account, this.identity, 42n);
      });

      it('returns true when no claim topic is required', async function () {
        await expect(this.registry.isVerified(this.account)).to.eventually.be.true;
      });

      describe('with a required claim topic', function () {
        beforeEach(async function () {
          await this.topics.connect(this.owner).addClaimTopic(KYC);
          await this.issuers.connect(this.owner).addTrustedIssuer(this.issuer, [KYC]);
          await this.identity.setClaim(KYC, this.issuer, signature, data);
          await this.issuer.setExpectedClaim(this.identity, KYC, signature, data);
        });

        it('returns true with a valid claim from a trusted issuer', async function () {
          await expect(this.registry.isVerified(this.account)).to.eventually.be.true;
        });

        it('returns false when the topic has no trusted issuer', async function () {
          await this.issuers.connect(this.owner).removeTrustedIssuer(this.issuer);
          await expect(this.registry.isVerified(this.account)).to.eventually.be.false;
        });

        it('returns false when the issuer is not trusted for the topic', async function () {
          await this.issuers.connect(this.owner).updateIssuerClaimTopics(this.issuer, [AML]);
          await expect(this.registry.isVerified(this.account)).to.eventually.be.false;
        });

        it('returns false when the identity holds no claim', async function () {
          await this.registry.connect(this.owner).updateIdentity(this.account, this.otherIdentity);
          await expect(this.registry.isVerified(this.account)).to.eventually.be.false;
        });

        it('returns false when the claim reports another topic', async function () {
          await this.identity.setClaimAt(claimId(this.issuer, KYC), AML, this.issuer);
          await expect(this.registry.isVerified(this.account)).to.eventually.be.false;
        });

        it('returns false when the claim reports another issuer', async function () {
          await this.identity.setClaimAt(claimId(this.issuer, KYC), KYC, this.otherIssuer);
          await expect(this.registry.isVerified(this.account)).to.eventually.be.false;
        });

        it('returns false when the identity reverts', async function () {
          await this.identity.setReverts(true);
          await expect(this.registry.isVerified(this.account)).to.eventually.be.false;
        });

        it('passes the claim to the issuer', async function () {
          await this.issuer.setExpectedClaim(this.identity, KYC, signature, '0x');
          await expect(this.registry.isVerified(this.account)).to.eventually.be.false;
        });

        for (const [name, answer] of Object.entries(Answer).filter(([name]) => name !== 'Valid')) {
          it(`returns false when the issuer answers ${name}`, async function () {
            await this.issuer.setAnswer(answer);
            await expect(this.registry.isVerified(this.account)).to.eventually.be.false;
          });
        }

        it('accepts a valid claim from any issuer trusted for the topic', async function () {
          await this.issuer.setAnswer(Answer.Revert);
          await this.issuers.connect(this.owner).addTrustedIssuer(this.otherIssuer, [KYC]);
          await expect(this.registry.isVerified(this.account)).to.eventually.be.false;

          await this.identity.setClaim(KYC, this.otherIssuer, signature, data);
          await this.otherIssuer.setExpectedClaim(this.identity, KYC, signature, data);
          await expect(this.registry.isVerified(this.account)).to.eventually.be.true;
        });

        it('requires a valid claim for every topic', async function () {
          await this.topics.connect(this.owner).addClaimTopic(AML);
          await expect(this.registry.isVerified(this.account)).to.eventually.be.false;

          await this.issuers.connect(this.owner).addTrustedIssuer(this.otherIssuer, [AML]);
          await this.identity.setClaim(AML, this.otherIssuer, signature, data);
          await this.otherIssuer.setExpectedClaim(this.identity, AML, signature, data);
          await expect(this.registry.isVerified(this.account)).to.eventually.be.true;
        });
      });
    });
  });
});

function claimId(issuer, topic) {
  return ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['address', 'uint256'], [issuer.target, topic]));
}
