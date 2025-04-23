const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

// These test vectors are derived from actual WebAuthn authentications
// From https://github.com/base/webauthn-sol/blob/main/test/WebAuthn.t.sol
const TEST_VECTORS = {
  safari: {
    challenge: '0xf631058a3ba1116acce12396fad0a125b5041c43f8e15723709f81aa8d5f4ccf',
    x: '28573233055232466711029625910063034642429572463461595413086259353299906450061',
    y: '39367742072897599771788408398752356480431855827262528811857788332151452825281',
    authenticatorData: '0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000101',
    clientDataJSON: {
      prefix: '{"type":"webauthn.get","challenge":"',
      suffix: '","origin":"http://localhost:3005"}',
    },
    challengeIndex: 23,
    typeIndex: 1,
    r: '43684192885701841787131392247364253107519555363555461570655060745499568693242',
    s: '22655632649588629308599201066602670461698485748654492451178007896016452673579',
  },
  chrome: {
    challenge: '0xf631058a3ba1116acce12396fad0a125b5041c43f8e15723709f81aa8d5f4ccf',
    x: '28573233055232466711029625910063034642429572463461595413086259353299906450061',
    y: '39367742072897599771788408398752356480431855827262528811857788332151452825281',
    authenticatorData: '0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d9763050000010a',
    clientDataJSON: {
      prefix: '{"type":"webauthn.get","challenge":"',
      suffix: '","origin":"http://localhost:3005","crossOrigin":false}',
    },
    challengeIndex: 23,
    typeIndex: 1,
    r: '29739767516584490820047863506833955097567272713519339793744591468032609909569',
    s: '45947455641742997809691064512762075989493430661170736817032030660832793108102',
  },
  // Invalid cases for testing failure modes
  invalidUp: {
    // User Present bit not set
    challenge: '0xf631058a3ba1116acce12396fad0a125b5041c43f8e15723709f81aa8d5f4ccf',
    x: '28573233055232466711029625910063034642429572463461595413086259353299906450061',
    y: '39367742072897599771788408398752356480431855827262528811857788332151452825281',
    authenticatorData: '0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000100', // UP bit not set
    clientDataJSON: {
      prefix: '{"type":"webauthn.get","challenge":"',
      suffix: '","origin":"http://localhost:3005"}',
    },
    challengeIndex: 23,
    typeIndex: 1,
    r: '43684192885701841787131392247364253107519555363555461570655060745499568693242',
    s: '22655632649588629308599201066602670461698485748654492451178007896016452673579',
  },
  invalidType: {
    // Wrong type - using webauthn.create instead of webauthn.get
    challenge: '0xf631058a3ba1116acce12396fad0a125b5041c43f8e15723709f81aa8d5f4ccf',
    x: '28573233055232466711029625910063034642429572463461595413086259353299906450061',
    y: '39367742072897599771788408398752356480431855827262528811857788332151452825281',
    authenticatorData: '0x49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000101',
    clientDataJSON: {
      prefix: '{"type":"webauthn.create","challenge":"',
      suffix: '","origin":"http://localhost:3005"}',
    },
    challengeIndex: 25, // Adjusted for the longer type string
    typeIndex: 1,
    r: '43684192885701841787131392247364253107519555363555461570655060745499568693242',
    s: '22655632649588629308599201066602670461698485748654492451178007896016452673579',
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
    r: BigInt(testVector.r),
    s: BigInt(testVector.s),
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

  describe('verify', function () {
    it('should validate Safari WebAuthn authentication', async function () {
      const vector = TEST_VECTORS.safari;
      const auth = createWebAuthnAuth(vector);

      expect(
        await this.webAuthnMock.$verify(
          vector.challenge,
          false, // requireUserVerification
          auth,
          BigInt(vector.x),
          BigInt(vector.y),
        ),
      ).to.be.true;
    });

    it('should validate Chrome WebAuthn authentication', async function () {
      const vector = TEST_VECTORS.chrome;
      const auth = createWebAuthnAuth(vector);

      expect(
        await this.webAuthnMock.$verify(
          vector.challenge,
          false, // requireUserVerification
          auth,
          BigInt(vector.x),
          BigInt(vector.y),
        ),
      ).to.be.true;
    });

    it('should require user verification when specified', async function () {
      const vector = TEST_VECTORS.safari;
      const auth = createWebAuthnAuth(vector);

      // This should pass because the test vector has UV bit set
      expect(
        await this.webAuthnMock.$verify(
          vector.challenge,
          true, // requireUserVerification
          auth,
          BigInt(vector.x),
          BigInt(vector.y),
        ),
      ).to.be.true;

      // Create modified auth data with UV bit cleared (replace bit 2)
      const authNoUV = { ...auth };
      const flagsByte = ethers.dataSlice(vector.authenticatorData, 32, 33);
      const originalFlags = ethers.getBigInt(flagsByte);
      const noUVFlags = originalFlags & ~BigInt(0x04); // Clear UV bit

      let authDataBytes = ethers.getBytes(vector.authenticatorData);
      authDataBytes[32] = Number(noUVFlags);
      authNoUV.authenticatorData = ethers.hexlify(authDataBytes);

      // This should fail because we require UV but the modified auth data doesn't have it
      expect(
        await this.webAuthnMock.$verify(
          vector.challenge,
          true, // requireUserVerification
          authNoUV,
          BigInt(vector.x),
          BigInt(vector.y),
        ),
      ).to.be.false;
    });

    it('should reject authentication without user present bit', async function () {
      const vector = TEST_VECTORS.invalidUp;
      const auth = createWebAuthnAuth(vector);

      expect(await this.webAuthnMock.$verify(vector.challenge, false, auth, BigInt(vector.x), BigInt(vector.y))).to.be
        .false;
    });

    it('should reject invalid type in clientDataJSON', async function () {
      const vector = TEST_VECTORS.invalidType;
      const auth = createWebAuthnAuth(vector);

      expect(await this.webAuthnMock.$verify(vector.challenge, false, auth, BigInt(vector.x), BigInt(vector.y))).to.be
        .false;
    });

    it('should reject invalid challenge', async function () {
      const vector = TEST_VECTORS.safari;
      // Create auth with wrong challenge encoding
      const auth = createWebAuthnAuth(vector, false);

      expect(await this.webAuthnMock.$verify(vector.challenge, false, auth, BigInt(vector.x), BigInt(vector.y))).to.be
        .false;
    });

    it('should reject if authenticator data is too short', async function () {
      const vector = TEST_VECTORS.safari;
      const auth = createWebAuthnAuth(vector);

      // Truncate authenticator data to make it too short
      auth.authenticatorData = ethers.dataSlice(vector.authenticatorData, 0, 30);

      expect(await this.webAuthnMock.$verify(vector.challenge, false, auth, BigInt(vector.x), BigInt(vector.y))).to.be
        .false;
    });
  });

  describe('Individual validation functions', function () {
    it('should correctly validate user present bit', async function () {
      expect(await this.webAuthnMock.$validateUserPresentBitSet('0x01')).to.be.true;
      expect(await this.webAuthnMock.$validateUserPresentBitSet('0x00')).to.be.false;
      expect(await this.webAuthnMock.$validateUserPresentBitSet('0x05')).to.be.true; // Other bits set too
    });

    it('should correctly validate user verified bit', async function () {
      // When requireUserVerification is true
      expect(await this.webAuthnMock.$validateUserVerifiedBit('0x04', true)).to.be.true;
      expect(await this.webAuthnMock.$validateUserVerifiedBit('0x00', true)).to.be.false;

      // When requireUserVerification is false
      expect(await this.webAuthnMock.$validateUserVerifiedBit('0x04', false)).to.be.true;
      expect(await this.webAuthnMock.$validateUserVerifiedBit('0x00', false)).to.be.true;
    });

    it('should correctly validate backup state bit logic', async function () {
      // Test all possible combinations of BE and BS bits

      // BE=1, BS=0: BE is set, BS is not set (valid)
      expect(await this.webAuthnMock.$validateBackupStateBit('0x08')).to.be.true;

      // BE=1, BS=1: BE is set, BS is set (valid)
      expect(await this.webAuthnMock.$validateBackupStateBit('0x18')).to.be.true;

      // BE=0, BS=0: BE is not set, BS is not set (valid)
      expect(await this.webAuthnMock.$validateBackupStateBit('0x00')).to.be.true;

      // BE=0, BS=1: BE is not set, BS is set (invalid)
      expect(await this.webAuthnMock.$validateBackupStateBit('0x10')).to.be.false;

      // Test with other bits set too
      expect(await this.webAuthnMock.$validateBackupStateBit('0x51')).to.be.false; // BE=0, BS=1, others=0x41
      expect(await this.webAuthnMock.$validateBackupStateBit('0x59')).to.be.true; // BE=1, BS=1, others=0x41
      expect(await this.webAuthnMock.$validateBackupStateBit('0x41')).to.be.true; // BE=0, BS=0, others=0x41
    });
  });
});
