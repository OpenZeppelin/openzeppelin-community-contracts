const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { shouldBehaveLikeERC7579Validator } = require('./ERC7579Module.behavior');
const { ERC4337Helper } = require('../../helpers/erc4337');
const { NonNativeSigner, P256SigningKey } = require('../../helpers/signers');
const { PackedUserOperation } = require('../../helpers/eip712-types');
const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');

async function fixture() {
  // ERC-7579 validator
  const mock = await ethers.deployContract('$ERC7579P256Validator');

  // ERC-4337 signer
  const signer = new NonNativeSigner(P256SigningKey.random());
  const publicKey = signer.signingKey.publicKey;

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const account = await helper
    .newAccount('$AccountERC7579Mock', [
      'AccountERC7579',
      '1',
      mock.target,
      ethers.AbiCoder.defaultAbiCoder().encode(['bytes32', 'bytes32'], [publicKey.qx, publicKey.qy]),
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

  return { ...env, mock, signer, publicKey, account, accountAsSigner, signUserOp, signUserOpHash };
}

describe('ERC7759P256Validator', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeERC7579Validator();

  it('associates an P256 signer from the account when calling onInstall', async function () {
    await expect(
      this.mock
        .connect(this.accountAsSigner)
        .onInstall(
          ethers.AbiCoder.defaultAbiCoder().encode(['bytes32', 'bytes32'], [this.publicKey.qx, this.publicKey.qy]),
        ),
    )
      .to.emit(this.mock, 'P256SignerAssociated')
      .withArgs(this.accountAsSigner, this.publicKey.qx, this.publicKey.qy);
    await expect(this.mock.signer(this.account)).to.eventually.deep.equal([this.publicKey.qx, this.publicKey.qy]);
  });

  it('disassociates an P256 signer from the account when calling onUninstall', async function () {
    const data = ethers.AbiCoder.defaultAbiCoder().encode(
      ['bytes32', 'bytes32'],
      [this.publicKey.qx, this.publicKey.qy],
    );
    await this.mock.connect(this.accountAsSigner).onInstall(data);
    await expect(this.mock.connect(this.accountAsSigner).onUninstall(data))
      .to.emit(this.mock, 'P256SignerAssociated')
      .withArgs(this.accountAsSigner, ethers.ZeroHash, ethers.ZeroHash);
    await expect(this.mock.signer(this.account)).to.eventually.deep.equal([ethers.ZeroHash, ethers.ZeroHash]);
  });
});
