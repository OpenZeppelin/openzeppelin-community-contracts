const { ethers } = require('hardhat');
const {
  shouldBehaveLikeAnAccountBase,
  shouldBehaveLikeAnAccountBaseExecutor,
  shouldBehaveLikeAccountHolder,
} = require('./Account.behavior');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ERC4337Helper } = require('../helpers/erc4337');
const { NonNativeSigner, RSASHA256SigningKey } = require('../helpers/signers');
const { shouldBehaveLikeERC7739Signer } = require('../utils/cryptography/ERC7739Signer.behavior');
const { PackedUserOperation } = require('../helpers/eip712');

async function fixture() {
  const [beneficiary, other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');
  const signer = new NonNativeSigner(RSASHA256SigningKey.random());
  const helper = new ERC4337Helper('$AccountRSAMock');
  const smartAccount = await helper.newAccount([
    'AccountRSA',
    '1',
    signer.signingKey.publicKey.e,
    signer.signingKey.publicKey.n,
  ]);
  const domain = {
    name: 'AccountRSA',
    version: '1',
    chainId: helper.chainId,
    verifyingContract: smartAccount.address,
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
      entrypoint: userOp.context.entrypoint.target,
    };
    userOp.signature = await signer.signTypedData(domain, types, typedOp);
    return userOp;
  };

  return { ...helper, domain, mock: smartAccount, signer, target, beneficiary, other, signUserOp };
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
