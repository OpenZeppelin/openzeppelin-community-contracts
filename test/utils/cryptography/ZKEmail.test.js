const { ethers } = require('hardhat');
// const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

// Values from https://github.com/zkemail/email-tx-builder/blob/main/packages/contracts/test/helpers/DeploymentHelper.sol
const selector = '12345';
const domainName = 'gmail.com';
const publicKeyHash = '0x0ea9c777dc7110e5a9e89b13f0cfc540e3845ba120b2b6dc24024d61488d4788';
const emailNullifier = '0x00a83fce3d4b1c9ef0f600644c1ecc6c8115b57b1596e0e3295e2c5105fbfd8a';
const accountSalt = '0x2c3abbf3d1171bfefee99c13bf9c47f1e8447576afd89096652a34f27b297971';
const templateId = ethers.solidityPackedKeccak256(['string', 'uint256'], ['test', 0n]);
// const :  = ['signHash', '{uint}'];

const select = (libraries, ...required) => Object.fromEntries(required.map(name => [name, libraries[name]]));

async function fixture() {
  const [admin, ...accounts] = await ethers.getSigners();

  const libraries = {};
  libraries.DecimalUtils = await ethers
    .getContractFactory('DecimalUtils', { libraries: [] })
    .then(factory => factory.deploy());
  libraries.CommandUtils = await ethers
    .getContractFactory('CommandUtils', { libraries: select(libraries, 'DecimalUtils') })
    .then(factory => factory.deploy());

  // Registry
  const dkim = await ethers.deployContract('ECDSAOwnedDKIMRegistry');
  await dkim.initialize(admin, admin);
  await dkim
    .SET_PREFIX()
    .then(prefix => dkim.computeSignedMsg(prefix, domainName, publicKeyHash))
    .then(message => admin.signMessage(message))
    .then(signature => dkim.setDKIMPublicKeyHash(selector, domainName, publicKeyHash, signature));

  // Verifier
  const groth16Verifier = await ethers.deployContract('Groth16Verifier');
  const verifier = await ethers.deployContract('Verifier');
  await verifier.initialize(admin, groth16Verifier);

  // Signer
  const signer = await ethers
    .getContractFactory('$SignerZKEmail', { libraries: select(libraries, 'CommandUtils') })
    .then(factory => factory.deploy());
  await this.signer.$_setAccountSalt(accountSalt);
  await this.signer.$_setDKIMRegistry(dkim);
  await this.signer.$_setVerifier(verifier);
  await this.signer.$_setCommandTemplate(templateId);

  return { admin, accounts, dkim, groth16Verifier, verifier, signer };
}

describe('ZKEmail', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('', async function () {
    console.log(this.dkim.target);
    console.log(this.verifier.target);

    const hash = ethers.hexlify(ethers.randomBytes(32));

    const emailAuthMsg = {
      templateId,
      commandParams: [hash],
      skippedCommandPrefix: 0,
      proof: {
        domainName,
        publicKeyHash,
        timestamp: 1694989812,
        maskedCommand: `signHash ${ethers.getBigInt(hash)}`,
        emailNullifier,
        accountSalt,
        isCodeExist: true,
        proof: '0x01',
      },
    };

    // Mock call on verifier?

    await this.signer.verifyEmail(emailAuthMsg);
  });
});
