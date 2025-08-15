const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { EmailProofError, Case } = require('../../helpers/enums');

const accountSalt = '0x046582bce36cdd0a8953b9d40b8f20d58302bacf3bcecffeb6741c98a52725e2'; // keccak256("test@example.com")

// From https://github.com/zkemail/email-tx-builder/blob/main/packages/contracts/test/helpers/DeploymentHelper.sol#L36-L41
const selector = '12345';
const domainName = 'gmail.com';
const publicKeyHash = '0x0ea9c777dc7110e5a9e89b13f0cfc540e3845ba120b2b6dc24024d61488d4788';
const emailNullifier = '0x00a83fce3d4b1c9ef0f600644c1ecc6c8115b57b1596e0e3295e2c5105fbfd8a';

const SIGN_HASH_COMMAND = 'signHash';
const UINT_MATCHER = '{uint}';
const ETH_ADDR_MATCHER = '{ethAddr}';

async function fixture() {
  const [admin, other, ...accounts] = await ethers.getSigners();

  // Registry
  const dkim = await ethers.deployContract('ECDSAOwnedDKIMRegistry');
  await dkim.initialize(admin, admin);
  await dkim
    .SET_PREFIX()
    .then(prefix => dkim.computeSignedMsg(prefix, domainName, publicKeyHash))
    .then(message => admin.signMessage(message))
    .then(signature => dkim.setDKIMPublicKeyHash(selector, domainName, publicKeyHash, signature));

  // Groth16 Verifier
  const verifier = await ethers.deployContract('ZKEmailGroth16VerifierMock');

  // Mock ZKEmailUtils
  const mock = await ethers.deployContract('$ZKEmailUtils');

  return { admin, other, accounts, dkim, verifier, mock };
}

function buildEmailProof(command) {
  // Values specific to ZKEmailGroth16VerifierMock
  const pA = [1n, 2n];
  const pB = [
    [3n, 4n],
    [5n, 6n],
  ];
  const pC = [7n, 8n];

  return {
    domainName,
    publicKeyHash,
    timestamp: Math.floor(Date.now() / 1000),
    maskedCommand: command,
    emailNullifier,
    accountSalt,
    isCodeExist: true,
    proof: ethers.AbiCoder.defaultAbiCoder().encode(['uint256[2]', 'uint256[2][2]', 'uint256[2]'], [pA, pB, pC]),
  };
}

describe('ZKEmailUtils', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('should validate ZKEmail sign hash', async function () {
    const hash = ethers.hexlify(ethers.randomBytes(32));
    const command = SIGN_HASH_COMMAND + ' ' + ethers.toBigInt(hash).toString();
    const emailProof = buildEmailProof(command);

    // Use the default function that handles signHash template internally
    const fnSig = '$isValidZKEmail((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,bytes32)';
    await expect(this.mock[fnSig](emailProof, this.dkim.target, this.verifier.target, hash)).to.eventually.equal(
      EmailProofError.NoError,
    );
  });

  it('should validate ZKEmail with template', async function () {
    const hash = ethers.hexlify(ethers.randomBytes(32));
    const commandPrefix = 'emailCommand';
    const command = commandPrefix + ' ' + ethers.toBigInt(hash).toString();
    const emailProof = buildEmailProof(command);
    const template = [commandPrefix, UINT_MATCHER];
    const templateParams = [ethers.AbiCoder.defaultAbiCoder().encode(['uint256'], [ethers.toBigInt(hash)])];

    const fnSig =
      '$isValidZKEmail((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,string[],bytes[])';
    await expect(
      this.mock[fnSig](emailProof, this.dkim.target, this.verifier.target, template, templateParams),
    ).to.eventually.equal(EmailProofError.NoError);
  });

  it('should validate complex email commands with multiple parameters', async function () {
    const amount = ethers.parseEther('2.5');
    const recipient = this.other.address;
    const command = `Send ${amount.toString()} ETH to ${recipient}`;
    const emailProof = buildEmailProof(command);
    const template = ['Send', UINT_MATCHER, 'ETH', 'to', ETH_ADDR_MATCHER];
    const templateParams = [
      ethers.AbiCoder.defaultAbiCoder().encode(['uint256'], [amount]),
      ethers.AbiCoder.defaultAbiCoder().encode(['address'], [recipient]),
    ];

    const fnSig =
      '$isValidZKEmail((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,string[],bytes[])';
    await expect(
      this.mock[fnSig](emailProof, this.dkim.target, this.verifier.target, template, templateParams),
    ).to.eventually.equal(EmailProofError.NoError);
  });

  it('should validate email maskedCommand from real proof structure', async function () {
    // Based on actual email verifier test: "Send 0.1 ETH to 0xafBD210c60dD651892a61804A989eEF7bD63CBA0"
    const amount = ethers.parseEther('0.1');
    const recipient = '0xafBD210c60dD651892a61804A989eEF7bD63CBA0';
    const command = `Send ${amount.toString()} ETH to ${recipient}`;
    const emailProof = buildEmailProof(command);
    const template = ['Send', UINT_MATCHER, 'ETH', 'to', ETH_ADDR_MATCHER];
    const templateParams = [
      ethers.AbiCoder.defaultAbiCoder().encode(['uint256'], [amount]),
      ethers.AbiCoder.defaultAbiCoder().encode(['address'], [recipient]),
    ];

    const fnSig =
      '$isValidZKEmail((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,string[],bytes[])';
    await expect(
      this.mock[fnSig](emailProof, this.dkim.target, this.verifier.target, template, templateParams),
    ).to.eventually.equal(EmailProofError.NoError);
  });

  it('should validate command with address match in different cases', async function () {
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
      const emailProof = buildEmailProof(command);
      const templateParams = [ethers.AbiCoder.defaultAbiCoder().encode(['address'], [address])];

      const fnSig =
        '$isValidZKEmail((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,string[],bytes[],uint8)';
      await expect(
        this.mock[fnSig](emailProof, this.dkim.target, this.verifier.target, template, templateParams, caseType),
      ).to.eventually.equal(EmailProofError.NoError);
    }
  });

  it('should validate command with address match using any case', async function () {
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
      const emailProof = buildEmailProof(command);
      const templateParams = [ethers.AbiCoder.defaultAbiCoder().encode(['address'], [address])];

      const fnSig =
        '$isValidZKEmail((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,string[],bytes[],uint8)';
      await expect(
        this.mock[fnSig](
          emailProof,
          this.dkim.target,
          this.verifier.target,
          template,
          templateParams,
          ethers.Typed.uint8(Case.ANY),
        ),
      ).to.eventually.equal(EmailProofError.NoError);
    }
  });

  it('should detect invalid DKIM public key hash', async function () {
    const hash = ethers.hexlify(ethers.randomBytes(32));
    const command = SIGN_HASH_COMMAND + ' ' + ethers.toBigInt(hash).toString();
    const emailProof = buildEmailProof(command);
    emailProof.publicKeyHash = ethers.hexlify(ethers.randomBytes(32)); // Invalid public key hash

    const template = [SIGN_HASH_COMMAND, UINT_MATCHER];
    const templateParams = [ethers.AbiCoder.defaultAbiCoder().encode(['uint256'], [ethers.toBigInt(hash)])];
    const fnSig =
      '$isValidZKEmail((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,string[],bytes[])';

    await expect(
      this.mock[fnSig](emailProof, this.dkim.target, this.verifier.target, template, templateParams),
    ).to.eventually.equal(EmailProofError.DKIMPublicKeyHash);
  });

  it('should detect unregistered domain', async function () {
    const hash = ethers.hexlify(ethers.randomBytes(32));
    const command = SIGN_HASH_COMMAND + ' ' + ethers.toBigInt(hash).toString();
    const emailProof = buildEmailProof(command);
    // Use a domain that hasn't been registered
    emailProof.domainName = 'unregistered-domain.com';

    const template = [SIGN_HASH_COMMAND, UINT_MATCHER];
    const templateParams = [ethers.AbiCoder.defaultAbiCoder().encode(['uint256'], [ethers.toBigInt(hash)])];
    const fnSig =
      '$isValidZKEmail((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,string[],bytes[])';

    await expect(
      this.mock[fnSig](emailProof, this.dkim.target, this.verifier.target, template, templateParams),
    ).to.eventually.equal(EmailProofError.DKIMPublicKeyHash);
  });

  it('should detect invalid masked command length', async function () {
    // Create a command that's too long (606 bytes)
    const longCommand = 'a'.repeat(606);
    const emailProof = buildEmailProof(longCommand);

    const template = ['a'.repeat(606)];
    const templateParams = [];
    const fnSig =
      '$isValidZKEmail((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,string[],bytes[])';

    await expect(
      this.mock[fnSig](emailProof, this.dkim.target, this.verifier.target, template, templateParams),
    ).to.eventually.equal(EmailProofError.MaskedCommandLength);
  });

  it('should detect mismatched command template', async function () {
    const hash = ethers.hexlify(ethers.randomBytes(32));
    const command = 'invalidEmailCommand ' + ethers.toBigInt(hash).toString();
    const emailProof = buildEmailProof(command);
    const template = ['differentCommand', UINT_MATCHER];
    const templateParams = [ethers.AbiCoder.defaultAbiCoder().encode(['uint256'], [ethers.toBigInt(hash)])];

    const fnSig =
      '$isValidZKEmail((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,string[],bytes[])';
    await expect(
      this.mock[fnSig](emailProof, this.dkim.target, this.verifier.target, template, templateParams),
    ).to.eventually.equal(EmailProofError.MismatchedCommand);
  });

  it('should detect invalid email proof', async function () {
    const hash = ethers.hexlify(ethers.randomBytes(32));
    const command = SIGN_HASH_COMMAND + ' ' + ethers.toBigInt(hash).toString();
    const emailProof = buildEmailProof(command);

    // Create invalid proof that will fail verification
    const pA = [1n, 1n];
    const pB = [
      [1n, 1n],
      [1n, 1n],
    ];
    const pC = [1n, 1n];
    const invalidProof = ethers.AbiCoder.defaultAbiCoder().encode(
      ['uint256[2]', 'uint256[2][2]', 'uint256[2]'],
      [pA, pB, pC],
    );
    emailProof.proof = invalidProof;

    const fnSig = '$isValidZKEmail((string,bytes32,uint256,string,bytes32,bytes32,bool,bytes),address,address,bytes32)';
    await expect(this.mock[fnSig](emailProof, this.dkim.target, this.verifier.target, hash)).to.eventually.equal(
      EmailProofError.EmailProof,
    );
  });
});
