const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { shouldBehaveLikeERC7579Validator } = require('./ERC7579Module.behavior');
const { ERC4337Helper } = require('../../helpers/erc4337');
const { NonNativeSigner, RSASHA256SigningKey } = require('../../helpers/signers');
const { PackedUserOperation } = require('../../helpers/eip712-types');
const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');

async function fixture() {
  // ERC-7579 validator
  const mock = await ethers.deployContract('$ERC7579RSAValidator');

  // ERC-4337 signer
  const signer = new NonNativeSigner(RSASHA256SigningKey.random());
  const publicKey = signer.signingKey.publicKey;

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const account = await helper
    .newAccount('$AccountERC7579Mock', [
      'AccountERC7579',
      '1',
      mock.target,
      ethers.AbiCoder.defaultAbiCoder().encode(['bytes', 'bytes'], [publicKey.e, publicKey.n]),
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

  return { ...env, mock, signer, publicKey, account, accountAsSigner, signUserOp };
}

describe('ERC7759Validator', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeERC7579Validator();

  it('associates an RSA signer from the account when calling onInstall', async function () {
    await expect(
      this.mock
        .connect(this.accountAsSigner)
        .onInstall(ethers.AbiCoder.defaultAbiCoder().encode(['bytes', 'bytes'], [this.publicKey.e, this.publicKey.n])),
    )
      .to.emit(this.mock, 'RSASignerAssociated')
      .withArgs(this.accountAsSigner, this.publicKey.e, this.publicKey.n);
    expect(this.mock.signer(this.account)).to.eventually.deep.equal([this.publicKey.e, this.publicKey.n]);
  });

  it('disassociates an RSA signer from the account when calling onUninstall', async function () {
    const data = ethers.AbiCoder.defaultAbiCoder().encode(['bytes', 'bytes'], [this.publicKey.e, this.publicKey.n]);
    this.mock.connect(this.accountAsSigner).onInstall(data);
    await expect(this.mock.connect(this.accountAsSigner).onUninstall(data))
      .to.emit(this.mock, 'RSASignerAssociated')
      .withArgs(this.accountAsSigner, '0x', '0x');
    expect(this.mock.signer(this.account)).to.eventually.deep.equal(['0x', '0x']);
  });
});
