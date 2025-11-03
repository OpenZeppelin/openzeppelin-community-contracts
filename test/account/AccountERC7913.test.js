const { ethers, predeploy } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { getDomain, PackedUserOperation } = require('@openzeppelin/contracts/test/helpers/eip712');
const { ERC4337Helper } = require('@openzeppelin/contracts/test/helpers/erc4337');
const { NonNativeSigner } = require('@openzeppelin/contracts/test/helpers/signers');
const { ZKEmailSigningKey } = require('../helpers/signers');

const {
  shouldBehaveLikeAccountCore,
  shouldBehaveLikeAccountHolder,
} = require('@openzeppelin/contracts/test/account/Account.behavior');
const { shouldBehaveLikeERC1271 } = require('@openzeppelin/contracts/test/utils/cryptography/ERC1271.behavior');
const { shouldBehaveLikeERC7821 } = require('@openzeppelin/contracts/test/account/extensions/ERC7821.behavior');

// Constants for ZKEmail
const accountSalt = '0x046582bce36cdd0a8953b9d40b8f20d58302bacf3bcecffeb6741c98a52725e2'; // keccak256("test@example.com")
const selector = '12345';
const domainName = 'gmail.com';
const publicKeyHash = '0x0ea9c777dc7110e5a9e89b13f0cfc540e3845ba120b2b6dc24024d61488d4788';
const emailNullifier = '0x00a83fce3d4b1c9ef0f600644c1ecc6c8115b57b1596e0e3295e2c5105fbfd8a';

// Prepare signer in advance
const signerZKEmail = new NonNativeSigner(
  new ZKEmailSigningKey(domainName, publicKeyHash, emailNullifier, accountSalt),
);

// Minimal fixture common to the different signer verifiers
async function fixture() {
  // EOAs and environment
  const [admin, beneficiary, other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMock');

  // DKIM Registry for ZKEmail
  const dkim = await ethers.deployContract('ECDSAOwnedDKIMRegistry');
  await dkim.initialize(admin, admin);
  await dkim
    .SET_PREFIX()
    .then(prefix => dkim.computeSignedMsg(prefix, domainName, publicKeyHash))
    .then(message => admin.signMessage(message))
    .then(signature => dkim.setDKIMPublicKeyHash(selector, domainName, publicKeyHash, signature));

  // ZKEmail Verifier
  const zkEmailVerifier = await ethers.deployContract('ZKEmailGroth16VerifierMock');

  // ERC-7913 verifiers
  const verifierZKEmail = await ethers.deployContract('$ERC7913ZKEmailVerifier');

  // ERC-4337 env
  const helper = new ERC4337Helper();
  await helper.wait();
  const entrypointDomain = await getDomain(predeploy.entrypoint.v08);
  const domain = { name: 'AccountERC7913', version: '1', chainId: entrypointDomain.chainId }; // Missing verifyingContract

  const makeMock = signer =>
    helper.newAccount('$AccountERC7913Mock', [signer, 'AccountERC7913', '1']).then(mock => {
      domain.verifyingContract = mock.address;
      return mock;
    });

  const signUserOp = function (userOp) {
    return this.signer
      .signTypedData(entrypointDomain, { PackedUserOperation }, userOp.packed)
      .then(signature => Object.assign(userOp, { signature }));
  };

  return {
    helper,
    verifierZKEmail,
    dkim,
    zkEmailVerifier,
    domain,
    target,
    beneficiary,
    other,
    makeMock,
    signUserOp,
  };
}

describe('AccountERC7913', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  // Using ZKEmail with an ERC-7913 verifier
  describe('ZKEmail', function () {
    beforeEach(async function () {
      // Create ZKEmail signer
      this.signer = signerZKEmail;

      // Create account with ZKEmail verifier
      this.mock = await this.makeMock(
        ethers.concat([
          this.verifierZKEmail.target,
          ethers.AbiCoder.defaultAbiCoder().encode(
            ['address', 'bytes32', 'address'],
            [this.dkim.target, accountSalt, this.zkEmailVerifier.target],
          ),
        ]),
      );

      // Override the signUserOp function to use the ZKEmail signer
      this.signUserOp = async userOp => {
        const hash = await userOp.hash();
        return Object.assign(userOp, { signature: this.signer.signingKey.sign(hash).serialized });
      };
    });

    shouldBehaveLikeAccountCore();
    shouldBehaveLikeAccountHolder();
    shouldBehaveLikeERC1271({ erc7739: true });
    shouldBehaveLikeERC7821();
  });
});
