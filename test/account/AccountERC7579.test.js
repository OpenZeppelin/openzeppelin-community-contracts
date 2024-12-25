const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ERC4337Helper } = require('../helpers/erc4337');
const { NonNativeSigner } = require('../helpers/signers');

const { shouldBehaveLikeAccountCore, shouldBehaveLikeAccountERC7579 } = require('./Account.behavior');

async function fixture() {
  // EOAs and environment
  const [beneficiary, other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-7579 validator
  const validatorMock = await ethers.deployContract('$ERC7579ValidatorMock');

  // ERC-4337 signer
  const signer = new NonNativeSigner({
    sign: () => ({ serialized: ethers.solidityPacked(['address', 'bool'], [validatorMock.target, '0x01']) }),
  });

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const mock = await helper.newAccount('$AccountERC7579Mock', ['AccountERC7579', '1', validatorMock.target, '0x']);

  // domain cannot be fetched using getDomain(mock) before the mock is deployed
  const domain = {
    name: 'AccountERC7579',
    version: '1',
    chainId: env.chainId,
    verifyingContract: mock.address,
  };

  const signUserOp = async userOp => {
    userOp.signature = await signer.signMessage(userOp.hash());
    return userOp;
  };

  return { ...env, mock, domain, signer, target, beneficiary, other, signUserOp };
}

describe('AccountERC7579', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeAccountCore();
  shouldBehaveLikeAccountERC7579();
});
