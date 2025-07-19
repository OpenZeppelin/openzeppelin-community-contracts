const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { JWTProofError, Case } = require('../../helpers/enums');

const accountSalt = '0x046582bce36cdd0a8953b9d40b8f20d58302bacf3bcecffeb6741c98a52725e2'; // keccak256("test@example.com")

// JWT-specific test data - using kid|iss|azp format (from actual zk-jwt tests)
const kid = '12345';
const iss = 'https://example.com';
const azp = 'client-id-12345';
const domainName = `${kid}|${iss}|${azp}`; // JWT format: kid|iss|azp
const publicKeyHash = '0x0ea9c777dc7110e5a9e89b13f0cfc540e3845ba120b2b6dc24024d61488d4788';
const emailNullifier = '0x00a83fce3d4b1c9ef0f600644c1ecc6c8115b57b1596e0e3295e2c5105fbfd8a';

const SIGN_HASH_COMMAND = 'signHash';
const UINT_MATCHER = '{uint}';
const ETH_ADDR_MATCHER = '{ethAddr}';

async function fixture() {
  const [admin, other, ...accounts] = await ethers.getSigners();

  // JWT Registry (following actual zk-jwt pattern from JwtRegistryBase.t.sol)
  const jwtRegistry = await ethers.deployContract('JwtRegistry', [admin.address]);

  // Set up the JWT public key following the actual test pattern
  await jwtRegistry
    .connect(admin)
    .setJwtPublicKey(domainName, publicKeyHash)
    .then(() => jwtRegistry.isDKIMPublicKeyHashValid(domainName, publicKeyHash))
    .then(() => jwtRegistry.isJwtPublicKeyValid(domainName, publicKeyHash));

  // JWT Verifier
  const verifier = await ethers.deployContract('ZKJWTVerifierMock');

  // ZKJWTUtils mock contract
  const mock = await ethers.deployContract('$ZKJWTUtils');

  return { admin, other, accounts, jwtRegistry, verifier, mock };
}

function buildJWTProof(command) {
  return {
    domainName, // kid|iss|azp format (from actual zk-jwt tests)
    publicKeyHash,
    timestamp: Math.floor(Date.now() / 1000),
    maskedCommand: command,
    emailNullifier,
    accountSalt,
    isCodeExist: true,
    proof: '0x01', // Mocked in ZKEmailVerifierMock
  };
}

describe('ZKJWTUtils', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('JWT Proof Validation', function () {
    it('should validate ZK JWT with default signHash template', async function () {
      const hash = ethers.hexlify(ethers.randomBytes(32));
      const command = SIGN_HASH_COMMAND + ' ' + ethers.toBigInt(hash).toString();
      const jwtProof = buildJWTProof(command);

      await expect(
        this.mock.$isValidZKJWT(jwtProof, this.jwtRegistry.target, this.verifier.target),
      ).to.eventually.equal(JWTProofError.NoError);
    });

    it('should validate ZK JWT with custom template', async function () {
      const hash = ethers.hexlify(ethers.randomBytes(32));
      const commandPrefix = 'jwtCommand';
      const command = commandPrefix + ' ' + ethers.toBigInt(hash).toString();
      const jwtProof = buildJWTProof(command);
      const template = [commandPrefix, UINT_MATCHER];

      const fnSig =
        '$isValidZKJWT((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,string[])';
      await expect(
        this.mock[fnSig](jwtProof, this.jwtRegistry.target, this.verifier.target, template),
      ).to.eventually.equal(JWTProofError.NoError);
    });

    it('should validate JWT command with address match in different cases', async function () {
      const commandPrefix = 'authorize';
      const template = [commandPrefix, ETH_ADDR_MATCHER];

      const testCases = [
        {
          caseType: Case.LOWERCASE,
          address: this.other.address.toLowerCase(),
        },
        {
          caseType: Case.UPPERCASE,
          address: this.other.address.toUpperCase().replace('0X', '0x'),
        },
        {
          caseType: Case.CHECKSUM,
          address: ethers.getAddress(this.other.address),
        },
      ];

      for (const { caseType, address } of testCases) {
        const command = commandPrefix + ' ' + address;
        const jwtProof = buildJWTProof(command);

        await expect(
          this.mock.$isValidZKJWT(jwtProof, this.jwtRegistry.target, this.verifier.target, template, caseType),
        ).to.eventually.equal(JWTProofError.NoError);
      }
    });

    it('should validate JWT command with address match using ANY case', async function () {
      const commandPrefix = 'grant';
      const template = [commandPrefix, ETH_ADDR_MATCHER];

      // Test with different cases that should all work with ANY case
      const addresses = [
        this.other.address.toLowerCase(),
        this.other.address.toUpperCase().replace('0X', '0x'),
        ethers.getAddress(this.other.address),
      ];

      for (const address of addresses) {
        const command = commandPrefix + ' ' + address;
        const jwtProof = buildJWTProof(command);

        await expect(
          this.mock.$isValidZKJWT(
            jwtProof,
            this.jwtRegistry.target,
            this.verifier.target,
            template,
            ethers.Typed.uint8(Case.ANY),
          ),
        ).to.eventually.equal(JWTProofError.NoError);
      }
    });
  });

  describe('JWT Error Handling', function () {
    it('should detect invalid JWT public key hash', async function () {
      const hash = ethers.hexlify(ethers.randomBytes(32));
      const command = SIGN_HASH_COMMAND + ' ' + ethers.toBigInt(hash).toString();
      const jwtProof = buildJWTProof(command);
      jwtProof.publicKeyHash = ethers.hexlify(ethers.randomBytes(32)); // Invalid public key hash

      await expect(
        this.mock.$isValidZKJWT(jwtProof, this.jwtRegistry.target, this.verifier.target),
      ).to.eventually.equal(JWTProofError.JWTPublicKeyHash);
    });

    it('should detect unregistered domain format', async function () {
      const hash = ethers.hexlify(ethers.randomBytes(32));
      const command = SIGN_HASH_COMMAND + ' ' + ethers.toBigInt(hash).toString();
      const jwtProof = buildJWTProof(command);
      // Use a domain that hasn't been registered
      jwtProof.domainName = 'unregistered-kid|https://unregistered.com|unregistered-client';

      await expect(
        this.mock.$isValidZKJWT(jwtProof, this.jwtRegistry.target, this.verifier.target),
      ).to.eventually.equal(JWTProofError.JWTPublicKeyHash);
    });

    it('should detect invalid masked command length', async function () {
      // Create a command that's too long (exceeds circuit limits - 605 bytes max)
      const longCommand = 'a'.repeat(606);
      const jwtProof = buildJWTProof(longCommand);

      await expect(
        this.mock.$isValidZKJWT(jwtProof, this.jwtRegistry.target, this.verifier.target),
      ).to.eventually.equal(JWTProofError.MaskedCommandLength);
    });

    it('should detect mismatched command template', async function () {
      const hash = ethers.hexlify(ethers.randomBytes(32));
      const command = 'invalidJWTCommand ' + ethers.toBigInt(hash).toString();
      const jwtProof = buildJWTProof(command);

      await expect(
        this.mock.$isValidZKJWT(jwtProof, this.jwtRegistry.target, this.verifier.target),
      ).to.eventually.equal(JWTProofError.MismatchedCommand);
    });

    it('should detect invalid JWT zero-knowledge proof', async function () {
      const hash = ethers.hexlify(ethers.randomBytes(32));
      const command = SIGN_HASH_COMMAND + ' ' + ethers.toBigInt(hash).toString();
      const jwtProof = buildJWTProof(command);
      jwtProof.proof = '0x00'; // Invalid proof that will fail verification

      await expect(
        this.mock.$isValidZKJWT(jwtProof, this.jwtRegistry.target, this.verifier.target),
      ).to.eventually.equal(JWTProofError.JWTProof);
    });
  });

  describe('JWT-Specific Domain Format', function () {
    it('should validate proper kid|iss|azp domain format', async function () {
      const hash = ethers.hexlify(ethers.randomBytes(32));
      const command = SIGN_HASH_COMMAND + ' ' + ethers.toBigInt(hash).toString();

      // Test various valid JWT domain formats
      const validDomains = [
        '12345|https://example.com|client-id-12345', // From actual tests
        'test-kid|https://accounts.google.com|1234567890.apps.googleusercontent.com', // Google
        'auth0-key|https://your-domain.auth0.com/|your-auth0-client-id', // Auth0
      ];

      for (const domain of validDomains) {
        const jwtProof = buildJWTProof(command);
        jwtProof.domainName = domain;

        await expect(
          this.mock.$isValidZKJWT(jwtProof, this.jwtRegistry.target, this.verifier.target),
        ).to.eventually.equal(JWTProofError.NoError);
      }
    });

    it('should handle JWT with real Google OAuth format', async function () {
      // Based on actual Google JWT structure
      const googleKid = 'google-key-id-123';
      const googleIss = 'https://accounts.google.com';
      const googleAzp = '1234567890.apps.googleusercontent.com';
      const googleDomain = `${googleKid}|${googleIss}|${googleAzp}`;

      const nonce = ethers.hexlify(ethers.randomBytes(16));
      const command = `grant ${nonce}`;
      const jwtProof = buildJWTProof(command);
      jwtProof.domainName = googleDomain;

      const template = ['grant', UINT_MATCHER];
      const fnSig =
        '$isValidZKJWT((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,string[])';

      await expect(
        this.mock[fnSig](jwtProof, this.jwtRegistry.target, this.verifier.target, template),
      ).to.eventually.equal(JWTProofError.NoError);
    });
  });

  describe('JWT Template Matching', function () {
    it('should validate complex JWT commands with multiple parameters', async function () {
      const amount = ethers.parseEther('1.5');
      const recipient = this.other.address;
      const command = `transfer ${amount.toString()} ${recipient}`;
      const jwtProof = buildJWTProof(command);
      const template = ['transfer', UINT_MATCHER, ETH_ADDR_MATCHER];

      const fnSig =
        '$isValidZKJWT((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,string[])';
      await expect(
        this.mock[fnSig](jwtProof, this.jwtRegistry.target, this.verifier.target, template),
      ).to.eventually.equal(JWTProofError.NoError);
    });

    it('should validate JWT maskedCommand from real proof structure', async function () {
      // Based on actual JWT verifier test: "Send 0.12 ETH to 0x1234"
      const command = 'Send 0.12 ETH to 0x1234';
      const jwtProof = buildJWTProof(command);
      const template = ['Send', UINT_MATCHER, 'ETH', 'to', ETH_ADDR_MATCHER];

      const fnSig =
        '$isValidZKJWT((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,string[])';
      await expect(
        this.mock[fnSig](jwtProof, this.jwtRegistry.target, this.verifier.target, template),
      ).to.eventually.equal(JWTProofError.NoError);
    });
  });
});
