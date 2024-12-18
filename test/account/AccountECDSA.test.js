const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ERC4337Helper } = require('../helpers/erc4337');
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
  const signer = ethers.Wallet.createRandom();
  const mock = await helper.newAccount('$AccountECDSAMock', ['AccountECDSA', '1', signer]);

  // domain cannot be fetched using getDomain(mock) before the mock is deployed
  const domain = {
    name: 'AccountECDSA',
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

  return {
    ...helper,
    domain,
    mock,
    signer,
    target,
    beneficiary,
    other,
    signUserOp,
  };
}

describe('AccountECDSA', function () {
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
