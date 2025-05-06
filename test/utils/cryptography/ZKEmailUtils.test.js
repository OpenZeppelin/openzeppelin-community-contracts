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

const templateId = ethers.solidityPackedKeccak256(['string', 'uint256'], ['TEST', 0n]);

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

  // Verifier
  const verifier = await ethers.deployContract('ZKEmailVerifierMock');

  // Mock
  const mock = await ethers.deployContract('$ZKEmailUtils');

  return { admin, other, accounts, dkim, verifier, mock };
}

function buildEmailAuthMsg(command, params, skippedPrefix) {
  const emailProof = {
    domainName,
    publicKeyHash,
    timestamp: Math.floor(Date.now() / 1000),
    maskedCommand: command,
    emailNullifier,
    accountSalt,
    isCodeExist: true,
    proof: '0x01', // Mocked in ZKEmailVerifierMock
  };

  return {
    templateId,
    commandParams: params,
    skippedCommandPrefix: skippedPrefix,
    proof: emailProof,
  };
}

describe('ZKEmail', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('should validate ZKEmail sign hash', async function () {
    const hash = ethers.hexlify(ethers.randomBytes(32));
    const emailAuthMsg = buildEmailAuthMsg(SIGN_HASH_COMMAND + ' ' + ethers.toBigInt(hash).toString(), [hash], 0);
    await expect(this.mock.$isValidZKEmail(emailAuthMsg, this.dkim.target, this.verifier.target)).to.eventually.equal(
      EmailProofError.NoError,
    );
  });

  it('should validate ZKEmail with template', async function () {
    const hash = ethers.hexlify(ethers.randomBytes(32));
    const commandPrefix = 'testCommand';
    const emailAuthMsg = buildEmailAuthMsg(commandPrefix + ' ' + ethers.toBigInt(hash).toString(), [hash], 0);
    const template = [commandPrefix, UINT_MATCHER];
    const fnSig =
      '$isValidZKEmail((uint256,bytes[],uint256,(string,bytes32,uint256,string,bytes32,bytes32,bool,bytes)),address,address,string[])';
    await expect(this.mock[fnSig](emailAuthMsg, this.dkim.target, this.verifier.target, template)).to.eventually.equal(
      EmailProofError.NoError,
    );
  });

  it('should validate command with address match with different cases', async function () {
    const commandPrefix = 'testCommand';
    const template = [commandPrefix, ETH_ADDR_MATCHER];

    for (const { caseType, address } of [
      {
        caseType: Case.LOWERCASE,
        address: this.other.address.toLowerCase(),
      },
      { caseType: Case.UPPERCASE, address: this.other.address.toUpperCase().replace('0X', '0x') },
      { caseType: Case.CHECKSUM, address: ethers.getAddress(this.other.address) },
    ]) {
      const emailAuthMsg = buildEmailAuthMsg(commandPrefix + ' ' + address, [ethers.zeroPadValue(address, 32)], 0);
      await expect(
        this.mock.$isValidZKEmail(emailAuthMsg, this.dkim.target, this.verifier.target, template, caseType),
      ).to.eventually.equal(EmailProofError.NoError);
    }
  });

  it('should validate command with address match with any case', async function () {
    const commandPrefix = 'testCommand';
    const template = [commandPrefix, ETH_ADDR_MATCHER];

    // Test with different cases that should all work with ANY case
    const addresses = [
      this.other.address.toLowerCase(),
      this.other.address.toUpperCase().replace('0X', '0x'),
      ethers.getAddress(this.other.address),
    ];

    for (const address of addresses) {
      const emailAuthMsg = buildEmailAuthMsg(commandPrefix + ' ' + address, [ethers.zeroPadValue(address, 32)], 0);
      await expect(
        this.mock.$isValidZKEmail(
          emailAuthMsg,
          this.dkim.target,
          this.verifier.target,
          template,
          ethers.Typed.uint8(Case.ANY),
        ),
      ).to.eventually.equal(EmailProofError.NoError);
    }
  });

  it('should detect invalid DKIM public key hash', async function () {
    const hash = ethers.hexlify(ethers.randomBytes(32));
    const emailAuthMsg = buildEmailAuthMsg(SIGN_HASH_COMMAND + ' ' + ethers.toBigInt(hash).toString(), [hash], 0);
    emailAuthMsg.proof.publicKeyHash = ethers.hexlify(ethers.randomBytes(32)); // Use a different public key hash
    await expect(this.mock.$isValidZKEmail(emailAuthMsg, this.dkim.target, this.verifier.target)).to.eventually.equal(
      EmailProofError.DKIMPublicKeyHash,
    );
  });

  it('should detect invalid masked command length', async function () {
    // Create a command that's too long (606 bytes)
    const longCommand = 'a'.repeat(606);
    const emailAuthMsg = buildEmailAuthMsg(longCommand, [ethers.hexlify(ethers.randomBytes(32))], 0);
    await expect(this.mock.$isValidZKEmail(emailAuthMsg, this.dkim.target, this.verifier.target)).to.eventually.equal(
      EmailProofError.MaskedCommandLength,
    );
  });

  it('should detect invalid skipped command prefix', async function () {
    const hash = ethers.hexlify(ethers.randomBytes(32));
    const commandBytes = await this.verifier.commandBytes();
    const emailAuthMsg = buildEmailAuthMsg(
      SIGN_HASH_COMMAND + ' ' + ethers.toBigInt(hash).toString(),
      [hash],
      BigInt(commandBytes) + 1n, // Set skipped prefix to be larger than commandBytes
    );
    await expect(this.mock.$isValidZKEmail(emailAuthMsg, this.dkim.target, this.verifier.target)).to.eventually.equal(
      EmailProofError.SkippedCommandPrefixSize,
    );
  });

  it('should detect mismatched command', async function () {
    const hash = ethers.hexlify(ethers.randomBytes(32));
    const emailAuthMsg = buildEmailAuthMsg('invalidCommand ' + ethers.toBigInt(hash).toString(), [hash], 0);
    await expect(this.mock.$isValidZKEmail(emailAuthMsg, this.dkim.target, this.verifier.target)).to.eventually.equal(
      EmailProofError.MismatchedCommand,
    );
  });

  it('should detect invalid email proof', async function () {
    const hash = ethers.hexlify(ethers.randomBytes(32));
    const emailAuthMsg = buildEmailAuthMsg(SIGN_HASH_COMMAND + ' ' + ethers.toBigInt(hash).toString(), [hash], 0);
    emailAuthMsg.proof.proof = '0x00'; // Use an invalid proof
    await expect(this.mock.$isValidZKEmail(emailAuthMsg, this.dkim.target, this.verifier.target)).to.eventually.equal(
      EmailProofError.EmailProof,
    );
  });
});
