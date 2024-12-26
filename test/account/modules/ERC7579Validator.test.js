const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { shouldBehaveLikeERC7579Validator } = require('./ERC7579Module.behavior');
const { NonNativeSigner } = require('../../helpers/signers');
const { ERC4337Helper } = require('../../helpers/erc4337');
const { PackedUserOperation } = require('../../helpers/eip712-types');

async function fixture() {
  // ERC-7579 validator
  const mock = await ethers.deployContract('$ERC7579ValidatorMock');

  // ERC-4337 signer
  const signer = new NonNativeSigner({
    sign: () => ({ serialized: ethers.solidityPacked(['address', 'bool'], [mock.target, '0x01']) }),
  });

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const account = await helper
    .newAccount('$AccountERC7579Mock', ['AccountERC7579', '1', mock.target, '0x'])
    .then(account => account.deploy());

  // domain cannot be fetched using getDomain(mock) before the mock is deployed
  const domain = {
    name: 'AccountERC7579',
    version: '1',
    chainId: env.chainId,
    verifyingContract: account.address,
  };

  const signUserOp = userOp =>
    signer
      .signTypedData(domain, { PackedUserOperation }, userOp.packed)
      .then(signature => Object.assign(userOp, { signature }));

  return { ...env, mock, signer, account, signUserOp };
}

describe('ERC7759Validator', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeERC7579Validator();
});
