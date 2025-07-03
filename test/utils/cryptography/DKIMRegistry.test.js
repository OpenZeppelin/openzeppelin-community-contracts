const { expect } = require('chai');
const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const DOMAIN_EXAMPLE_COM = ethers.keccak256(ethers.toUtf8Bytes('example.com'));
const DOMAIN_EXAMPLE_ORG = ethers.keccak256(ethers.toUtf8Bytes('example.org'));
const DOMAIN_SUBDOMAIN = ethers.keccak256(ethers.toUtf8Bytes('mail.example.com'));

const KEY_HASH_1 = ethers.keccak256(ethers.toUtf8Bytes('dkim_public_key_1'));
const KEY_HASH_2 = ethers.keccak256(ethers.toUtf8Bytes('dkim_public_key_2'));
const KEY_HASH_3 = ethers.keccak256(ethers.toUtf8Bytes('dkim_public_key_3'));
const ZERO_HASH = ethers.ZeroHash;

async function fixture() {
  const registry = await ethers.deployContract('$DKIMRegistry');

  return { registry };
}

describe('DKIMRegistry', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('isKeyHashValid', function () {
    it('should return false for unregistered key hash', async function () {
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.false;
    });

    it('should return true for registered key hash', async function () {
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
    });

    it('should return false for different domain with same key hash', async function () {
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_ORG, KEY_HASH_1)).to.eventually.be.false;
    });

    it('should return false for same domain with different key hash', async function () {
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_2)).to.eventually.be.false;
    });

    it('should handle zero hash values', async function () {
      await expect(this.registry.isKeyHashValid(ZERO_HASH, ZERO_HASH)).to.eventually.be.false;

      await this.registry.$_setKeyHash(ZERO_HASH, ZERO_HASH);
      await expect(this.registry.isKeyHashValid(ZERO_HASH, ZERO_HASH)).to.eventually.be.true;
    });
  });

  describe('_setKeyHash', function () {
    it('should set a key hash for a domain', async function () {
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
    });

    it('should emit KeyHashRegistered event', async function () {
      await expect(this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1))
        .to.emit(this.registry, 'KeyHashRegistered')
        .withArgs(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
    });

    it('should allow setting multiple key hashes for same domain', async function () {
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_2);

      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_2)).to.eventually.be.true;
    });

    it('should allow setting same key hash for different domains', async function () {
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_ORG, KEY_HASH_1);

      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_ORG, KEY_HASH_1)).to.eventually.be.true;
    });

    it('should handle subdomains independently', async function () {
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
      await this.registry.$_setKeyHash(DOMAIN_SUBDOMAIN, KEY_HASH_2);

      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
      await expect(this.registry.isKeyHashValid(DOMAIN_SUBDOMAIN, KEY_HASH_2)).to.eventually.be.true;
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_2)).to.eventually.be.false;
      await expect(this.registry.isKeyHashValid(DOMAIN_SUBDOMAIN, KEY_HASH_1)).to.eventually.be.false;
    });

    it('should allow setting zero hash', async function () {
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, ZERO_HASH);
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, ZERO_HASH)).to.eventually.be.true;
    });

    it('should overwrite existing key hash', async function () {
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1); // Set again

      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
    });
  });

  describe('_setKeyHashes', function () {
    it('should set multiple key hashes for a domain', async function () {
      const keyHashes = [KEY_HASH_1, KEY_HASH_2, KEY_HASH_3];
      await this.registry.$_setKeyHashes(DOMAIN_EXAMPLE_COM, keyHashes);

      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_2)).to.eventually.be.true;
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_3)).to.eventually.be.true;
    });

    it('should emit KeyHashRegistered event for each key hash', async function () {
      const keyHashes = [KEY_HASH_1, KEY_HASH_2];
      const tx = this.registry.$_setKeyHashes(DOMAIN_EXAMPLE_COM, keyHashes);

      await expect(tx).to.emit(this.registry, 'KeyHashRegistered').withArgs(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
      await expect(tx).to.emit(this.registry, 'KeyHashRegistered').withArgs(DOMAIN_EXAMPLE_COM, KEY_HASH_2);
    });

    it('should handle single key hash in array', async function () {
      const keyHashes = [KEY_HASH_1];
      await this.registry.$_setKeyHashes(DOMAIN_EXAMPLE_COM, keyHashes);

      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
    });

    it('should handle empty array', async function () {
      const keyHashes = [];
      await this.registry.$_setKeyHashes(DOMAIN_EXAMPLE_COM, keyHashes);

      // No key hashes should be set
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.false;
    });

    it('should handle duplicate key hashes in array', async function () {
      const keyHashes = [KEY_HASH_1, KEY_HASH_1, KEY_HASH_2];
      await this.registry.$_setKeyHashes(DOMAIN_EXAMPLE_COM, keyHashes);

      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_2)).to.eventually.be.true;
    });

    it('should handle array with zero hash', async function () {
      const keyHashes = [KEY_HASH_1, ZERO_HASH, KEY_HASH_2];
      await this.registry.$_setKeyHashes(DOMAIN_EXAMPLE_COM, keyHashes);

      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, ZERO_HASH)).to.eventually.be.true;
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_2)).to.eventually.be.true;
    });
  });

  describe('_revokeKeyHash', function () {
    beforeEach(async function () {
      // Set up some key hashes to revoke
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_2);
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_ORG, KEY_HASH_1);
    });

    it('should revoke a key hash for a domain', async function () {
      await this.registry.$_revokeKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);

      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.false;
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_2)).to.eventually.be.true; // Other key should remain
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_ORG, KEY_HASH_1)).to.eventually.be.true; // Same key on different domain should remain
    });

    it('should emit KeyHashRevoked event', async function () {
      await expect(this.registry.$_revokeKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1))
        .to.emit(this.registry, 'KeyHashRevoked')
        .withArgs(DOMAIN_EXAMPLE_COM);
    });

    it('should handle revoking non-existent key hash', async function () {
      await this.registry.$_revokeKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_3);

      // Should not affect existing key hashes
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_2)).to.eventually.be.true;
    });

    it('should handle revoking from non-existent domain', async function () {
      const nonExistentDomain = ethers.keccak256(ethers.toUtf8Bytes('nonexistent.com'));
      await this.registry.$_revokeKeyHash(nonExistentDomain, KEY_HASH_1);

      // Should not affect existing key hashes
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
    });

    it('should handle revoking zero hash', async function () {
      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, ZERO_HASH);
      await this.registry.$_revokeKeyHash(DOMAIN_EXAMPLE_COM, ZERO_HASH);

      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, ZERO_HASH)).to.eventually.be.false;
    });

    it('should allow re-setting a revoked key hash', async function () {
      await this.registry.$_revokeKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.false;

      await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
      await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
    });
  });

  it('should handle multiple domains with overlapping key hashes', async function () {
    // Set same key hash for multiple domains
    await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);
    await this.registry.$_setKeyHash(DOMAIN_EXAMPLE_ORG, KEY_HASH_1);
    await this.registry.$_setKeyHash(DOMAIN_SUBDOMAIN, KEY_HASH_1);

    // Verify all are valid
    await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
    await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_ORG, KEY_HASH_1)).to.eventually.be.true;
    await expect(this.registry.isKeyHashValid(DOMAIN_SUBDOMAIN, KEY_HASH_1)).to.eventually.be.true;

    // Revoke from one domain only
    await this.registry.$_revokeKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_1);

    await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.false;
    await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_ORG, KEY_HASH_1)).to.eventually.be.true;
    await expect(this.registry.isKeyHashValid(DOMAIN_SUBDOMAIN, KEY_HASH_1)).to.eventually.be.true;
  });

  it('should handle batch operations followed by individual revocations', async function () {
    const keyHashes = [KEY_HASH_1, KEY_HASH_2, KEY_HASH_3];
    await this.registry.$_setKeyHashes(DOMAIN_EXAMPLE_COM, keyHashes);

    // Verify all are set
    await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
    await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_2)).to.eventually.be.true;
    await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_3)).to.eventually.be.true;

    // Revoke middle key hash
    await this.registry.$_revokeKeyHash(DOMAIN_EXAMPLE_COM, KEY_HASH_2);

    await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_1)).to.eventually.be.true;
    await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_2)).to.eventually.be.false;
    await expect(this.registry.isKeyHashValid(DOMAIN_EXAMPLE_COM, KEY_HASH_3)).to.eventually.be.true;
  });
});
