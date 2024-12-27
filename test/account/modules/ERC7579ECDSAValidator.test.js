const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { shouldBehaveLikeERC7579Validator } = require('./ERC7579Module.behavior');
const { ERC4337Helper } = require('../../helpers/erc4337');
const { PackedUserOperation } = require('../../helpers/eip712-types');
const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');

async function fixture() {
  // ERC-7579 validator
  const mock = await ethers.deployContract('$ERC7579ECDSAValidator');

  // ERC-4337 signer
  const signer = ethers.Wallet.createRandom();

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const account = await helper
    .newAccount('$AccountERC7579Mock', [
      'AccountERC7579',
      '1',
      mock.target,
      ethers.solidityPacked(['address'], [signer.address]),
    ])
    .then(account => account.deploy());

  const accountAsSigner = await impersonate(account.address);

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

  const signUserOpHash = userOp => ethers.TypedDataEncoder.hash(domain, { PackedUserOperation }, userOp.packed);

  return { ...env, mock, signer, account, accountAsSigner, signUserOp, signUserOpHash };
}

describe('ERC7759ECDSAValidator', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeERC7579Validator();

  it('associates an ECDSA signer from the account when calling onInstall', async function () {
    await expect(
      this.mock.connect(this.accountAsSigner).onInstall(ethers.solidityPacked(['address'], [this.signer.address])),
    )
      .to.emit(this.mock, 'ECDSASignerAssociated')
      .withArgs(this.accountAsSigner, this.signer);
    await expect(this.mock.signer(this.account)).to.eventually.equal(this.signer.address);
  });

  it('disassociates an ECDSA signer from the account when calling onUninstall', async function () {
    const data = ethers.solidityPacked(['address'], [this.signer.address]);
    this.mock.connect(this.accountAsSigner).onInstall(data);
    await expect(this.mock.connect(this.accountAsSigner).onUninstall(data))
      .to.emit(this.mock, 'ECDSASignerAssociated')
      .withArgs(this.accountAsSigner, ethers.ZeroAddress);
    await expect(this.mock.signer(this.account)).to.eventually.equal(ethers.ZeroAddress);
  });
});
