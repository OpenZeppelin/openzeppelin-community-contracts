const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ERC4337Helper } = require('../helpers/erc4337');
const { NonNativeSigner, RSASHA256SigningKey } = require('../helpers/signers');
const { PackedUserOperation } = require('../helpers/eip712-types');

const {
  shouldBehaveLikeAnAccountBase,
  shouldBehaveLikeAnAccountBaseExecutor,
  shouldBehaveLikeAccountHolder,
} = require('./Account.behavior');
const { shouldBehaveLikeERC7739Signer } = require('../utils/cryptography/ERC7739Signer.behavior');

async function fixture() {
  // EOAs and environment
  const [beneficiary, other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-4337 signer and account
  const helper = new ERC4337Helper();
  await helper.wait();
  const signer = new NonNativeSigner(RSASHA256SigningKey.random());
  const mock = await helper.newAccount('$AccountRSAMock', [
    'AccountRSA',
    '1',
    signer.signingKey.publicKey.e,
    signer.signingKey.publicKey.n,
  ]);

  // domain cannot be fetched using getDomain(mock) before the mock is deployed
  const domain = {
    name: 'AccountRSA',
    version: '1',
    chainId: helper.chainId,
    verifyingContract: mock.address,
  };

  const signUserOp = async userOp => {
    const types = { PackedUserOperation };
    const packed = userOp.packed;
    const typedOp = {
      sender: packed.sender,
      nonce: packed.nonce,
      initCode: packed.initCode,
      callData: packed.callData,
      accountGasLimits: packed.accountGasLimits,
      preVerificationGas: packed.preVerificationGas,
      gasFees: packed.gasFees,
      paymasterAndData: packed.paymasterAndData,
      entrypoint: helper.entrypoint.target,
    };
    userOp.signature = await signer.signTypedData(domain, types, typedOp);
    return userOp;
  };

  return { ...helper, domain, mock, signer, target, beneficiary, other, signUserOp };
}

describe('AccountRSA', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeAnAccountBase();
  shouldBehaveLikeAnAccountBaseExecutor();
  shouldBehaveLikeAccountHolder();

  describe('ERC7739Signer', function () {
    beforeEach(async function () {
      this.mock = await this.mock.deploy();
      this.signTypedData = this.signer.signTypedData.bind(this.signer);
    });

    shouldBehaveLikeERC7739Signer();
  });
});
