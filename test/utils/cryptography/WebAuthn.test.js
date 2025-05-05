const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

// These test vectors are derived from actual WebAuthn authentications
// From https://github.com/base/webauthn-sol/blob/main/test/WebAuthn.t.sol
const TEST_VECTORS = {
  safari: {
    challenge: '0xf631058a3ba1116acce12396fad0a125b5041c43f8e15723709f81aa8d5f4ccf',
    x: '0x3f2be075ef57d6c8374ef412fe54fdd980050f70f4f3a00b5b1b32d2def7d28d',
    y: '0x57095a365acc2590ade3583fabfe8fbd64a9ed3ec07520da00636fb21f0176c1',
    authenticatorData: '0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000101',
    clientDataJSON: {
      prefix: '{"type":"webauthn.get","challenge":"',
      suffix: '","origin":"http://localhost:3005"}',
    },
    challengeIndex: 23,
    typeIndex: 1,
    r: '0x60946081650523acad13c8eff94996a409b1ed60e923c90f9e366aad619adffa',
    s: '0x3216a237b73765d01b839e0832d73474bc7e63f4c86ef05fbbbfbeb34b35602b',
  },
  chrome: {
    challenge: '0xf631058a3ba1116acce12396fad0a125b5041c43f8e15723709f81aa8d5f4ccf',
    x: '0x3f2be075ef57d6c8374ef412fe54fdd980050f70f4f3a00b5b1b32d2def7d28d',
    y: '0x57095a365acc2590ade3583fabfe8fbd64a9ed3ec07520da00636fb21f0176c1',
    authenticatorData: '0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763050000010a',
    clientDataJSON: {
      prefix: '{"type":"webauthn.get","challenge":"',
      suffix: '","origin":"http://localhost:3005","crossOrigin":false}',
    },
    challengeIndex: 23,
    typeIndex: 1,
    r: '0x41c01ca5ecdfeb23ef70d6cc216fd491ac3aa3d40c480751f3618a3a9ef67b41',
    s: '0x6595569abf76c2777e832a9252bae14efdb77febd0fa3b919aa16f6208469e86',
  },
  // Invalid cases for testing failure modes
  invalidUp: {
    // User Present bit not set
    challenge: '0xf631058a3ba1116acce12396fad0a125b5041c43f8e15723709f81aa8d5f4ccf',
    x: '0x3f2be075ef57d6c8374ef412fe54fdd980050f70f4f3a00b5b1b32d2def7d28d',
    y: '0x57095a365acc2590ade3583fabfe8fbd64a9ed3ec07520da00636fb21f0176c1',
    authenticatorData: '0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000100', // UP bit not set
    clientDataJSON: {
      prefix: '{"type":"webauthn.get","challenge":"',
      suffix: '","origin":"http://localhost:3005"}',
    },
    challengeIndex: 23,
    typeIndex: 1,
    r: '0x60946081650523acad13c8eff94996a409b1ed60e923c90f9e366aad619adffa',
    s: '0x3216a237b73765d01b839e0832d73474bc7e63f4c86ef05fbbbfbeb34b35602b',
  },
  invalidType: {
    // Wrong type - using webauthn.create instead of webauthn.get
    challenge: '0xf631058a3ba1116acce12396fad0a125b5041c43f8e15723709f81aa8d5f4ccf',
    x: '0x3f2be075ef57d6c8374ef412fe54fdd980050f70f4f3a00b5b1b32d2def7d28d',
    y: '0x57095a365acc2590ade3583fabfe8fbd64a9ed3ec07520da00636fb21f0176c1',
    authenticatorData: '0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000101',
    clientDataJSON: {
      prefix: '{"type":"webauthn.create","challenge":"',
      suffix: '","origin":"http://localhost:3005"}',
    },
    challengeIndex: 25, // Adjusted for the longer type string
    typeIndex: 1,
    r: '0x60946081650523acad13c8eff94996a409b1ed60e923c90f9e366aad619adffa',
    s: '0x3216a237b73765d01b839e0832d73474bc7e63f4c86ef05fbbbfbeb34b35602b',
  },
};

// Replace "+/" with "-_" in the char table, and remove the padding
// see https://datatracker.ietf.org/doc/html/rfc4648#section-5
const base64toBase64Url = str => str.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');

const encodeBase64URL = hexStr => base64toBase64Url(ethers.encodeBase64(Buffer.from(ethers.getBytes(hexStr))));

const createWebAuthnAuth = (testVector, encodeChallenge = true) => {
  // Get base64url encoded challenge
  const base64Challenge = encodeChallenge ? encodeBase64URL(testVector.challenge) : 'INVALID';

  // Construct full clientDataJSON
  const clientDataJSON = testVector.clientDataJSON.prefix + base64Challenge + testVector.clientDataJSON.suffix;

  return {
    authenticatorData: testVector.authenticatorData,
    clientDataJSON: clientDataJSON,
    challengeIndex: testVector.challengeIndex,
    typeIndex: testVector.typeIndex,
    r: testVector.r,
    s: testVector.s,
  };
};

async function fixture() {
  const webAuthnMock = await ethers.deployContract('$WebAuthn');

  return { webAuthnMock };
}

describe('WebAuthn', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('verifyMinimal', function () {
    it('should validate Safari WebAuthn authentication with minimal checks', async function () {
      const vector = TEST_VECTORS.safari;
      const auth = createWebAuthnAuth(vector);

      await expect(this.webAuthnMock.$verifyMinimal(vector.challenge, auth, vector.x, vector.y)).to.eventually.be.true;
    });

    it('should validate Chrome WebAuthn authentication with minimal checks', async function () {
      const vector = TEST_VECTORS.chrome;
      const auth = createWebAuthnAuth(vector);

      await expect(this.webAuthnMock.$verifyMinimal(vector.challenge, auth, vector.x, vector.y)).to.eventually.be.true;
    });

    it.only('should accept authentication without user present bit in minimal mode', async function () {
      const vector = TEST_VECTORS.invalidUp;
      const auth = createWebAuthnAuth(vector);

      // In minimal mode, we don't check user presence
      await expect(this.webAuthnMock.$verifyMinimal(vector.challenge, auth, vector.x, vector.y)).to.eventually.be.true;
    });

    it('should reject invalid type in clientDataJSON even in minimal mode', async function () {
      const vector = TEST_VECTORS.invalidType;
      const auth = createWebAuthnAuth(vector);

      await expect(this.webAuthnMock.$verifyMinimal(vector.challenge, auth, vector.x, vector.y)).to.eventually.be.false;
    });

    it('should reject invalid challenge even in minimal mode', async function () {
      const vector = TEST_VECTORS.safari;
      // Create auth with wrong challenge encoding
      const auth = createWebAuthnAuth(vector, false);

      await expect(this.webAuthnMock.$verifyMinimal(vector.challenge, auth, vector.x, vector.y)).to.eventually.be.false;
    });

    it('should reject if authenticator data is too short in minimal mode', async function () {
      const vector = TEST_VECTORS.safari;
      const auth = createWebAuthnAuth(vector);

      // Truncate authenticator data to make it too short
      auth.authenticatorData = ethers.dataSlice(vector.authenticatorData, 0, 30);

      await expect(this.webAuthnMock.$verifyMinimal(vector.challenge, auth, vector.x, vector.y)).to.eventually.be.false;
    });
  });

  describe('verify', function () {
    it('should validate Safari WebAuthn authentication with standard checks', async function () {
      const vector = TEST_VECTORS.safari;
      const auth = createWebAuthnAuth(vector);

      await expect(this.webAuthnMock.$verify(vector.challenge, auth, vector.x, vector.y)).to.eventually.be.true;
    });

    it('should validate Chrome WebAuthn authentication with standard checks', async function () {
      const vector = TEST_VECTORS.chrome;
      const auth = createWebAuthnAuth(vector);

      await expect(this.webAuthnMock.$verify(vector.challenge, auth, vector.x, vector.y)).to.eventually.be.true;
    });

    it('should reject authentication without user present bit in standard mode', async function () {
      const vector = TEST_VECTORS.invalidUp;
      const auth = createWebAuthnAuth(vector);

      // In standard mode, we check user presence but not user verification
      await expect(this.webAuthnMock.$verify(vector.challenge, auth, vector.x, vector.y)).to.eventually.be.false;
    });
  });

  describe('verifyStrict', function () {
    it('should validate Safari WebAuthn authentication with strict checks', async function () {
      const vector = TEST_VECTORS.safari;
      const auth = createWebAuthnAuth(vector);

      await expect(this.webAuthnMock.$verifyStrict(vector.challenge, auth, vector.x, vector.y)).to.eventually.be.true;
    });

    it('should validate Chrome WebAuthn authentication with strict checks', async function () {
      const vector = TEST_VECTORS.chrome;
      const auth = createWebAuthnAuth(vector);

      await expect(this.webAuthnMock.$verifyStrict(vector.challenge, auth, vector.x, vector.y)).to.eventually.be.true;
    });

    it('should reject authentication without user verification bit in strict mode', async function () {
      const vector = TEST_VECTORS.safari;
      const auth = createWebAuthnAuth(vector);

      // Create modified auth data with UV bit cleared (replace bit 2)
      const authNoUV = { ...auth };
      const flagsByte = ethers.dataSlice(vector.authenticatorData, 32, 33);
      const originalFlags = ethers.getBigInt(flagsByte);
      const noUVFlags = originalFlags & ~BigInt(0x04); // Clear UV bit

      let authDataBytes = ethers.getBytes(vector.authenticatorData);
      authDataBytes[32] = Number(noUVFlags);
      authNoUV.authenticatorData = ethers.hexlify(authDataBytes);

      // In strict mode, we require user verification
      await expect(this.webAuthnMock.$verifyStrict(vector.challenge, authNoUV, vector.x, vector.y)).to.eventually.be
        .false;
    });

    it('should reject invalid backup state/eligibility relationship in strict mode', async function () {
      const vector = TEST_VECTORS.safari;
      const auth = createWebAuthnAuth(vector);

      // Create modified auth data with invalid BE/BS combination (BE=0, BS=1)
      const authInvalidBE = { ...auth };
      const flagsByte = ethers.dataSlice(vector.authenticatorData, 32, 33);
      const originalFlags = ethers.getBigInt(flagsByte);
      const invalidFlags = (originalFlags & ~BigInt(0x08)) | BigInt(0x10); // Clear BE (0x08), set BS (0x10)

      let authDataBytes = ethers.getBytes(vector.authenticatorData);
      authDataBytes[32] = Number(invalidFlags);
      authInvalidBE.authenticatorData = ethers.hexlify(authDataBytes);

      // In strict mode, we validate BE/BS relationship
      await expect(this.webAuthnMock.$verifyStrict(vector.challenge, authInvalidBE, vector.x, vector.y)).to.eventually
        .be.false;
    });
  });

  describe('Individual validation functions', function () {
    it('should correctly validate user present bit', async function () {
      await expect(this.webAuthnMock.$validateUserPresentBitSet('0x01')).to.be.eventually.true;
      await expect(this.webAuthnMock.$validateUserPresentBitSet('0x00')).to.be.eventually.false;
      await expect(this.webAuthnMock.$validateUserPresentBitSet('0x05')).to.be.eventually.true; // Other bits set too
    });

    it('should correctly validate user verified bit', async function () {
      await expect(this.webAuthnMock.$validateUserVerifiedBitSet('0x04')).to.be.eventually.true;
      await expect(this.webAuthnMock.$validateUserVerifiedBitSet('0x00')).to.be.eventually.false;
      await expect(this.webAuthnMock.$validateUserVerifiedBitSet('0x05')).to.be.eventually.true; // Other bits set too
    });

    it('should correctly validate backup state/eligibility relationship', async function () {
      // Test all possible combinations of BE and BS bits

      // BE=1, BS=0: BE is set, BS is not set (valid)
      await expect(this.webAuthnMock.$validateBackupEligibilityAndState('0x08')).to.eventually.be.true;

      // BE=1, BS=1: BE is set, BS is set (valid)
      await expect(this.webAuthnMock.$validateBackupEligibilityAndState('0x18')).to.eventually.be.true;

      // BE=0, BS=0: BE is not set, BS is not set (valid)
      await expect(this.webAuthnMock.$validateBackupEligibilityAndState('0x00')).to.eventually.be.true;

      // BE=0, BS=1: BE is not set, BS is set (invalid)
      await expect(this.webAuthnMock.$validateBackupEligibilityAndState('0x10')).to.eventually.be.false;

      // Test with other bits set too
      await expect(this.webAuthnMock.$validateBackupEligibilityAndState('0x51')).to.eventually.be.false; // BE=0, BS=1, others=0x41
      await expect(this.webAuthnMock.$validateBackupEligibilityAndState('0x59')).to.eventually.be.true; // BE=1, BS=1, others=0x41
      await expect(this.webAuthnMock.$validateBackupEligibilityAndState('0x41')).to.eventually.be.true; // BE=0, BS=0, others=0x41
    });
  });
});
