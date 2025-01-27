const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { shouldBehaveLikePaymaster } = require('./Paymaster.behavior');
const { ERC4337Helper } = require('../../helpers/erc4337');
const { NonNativeSigner } = require('../../helpers/signers');

async function fixture() {
  // EOAs and environment
  const [depositor, staker, receiver] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-4337 signer
  const accountSigner = new NonNativeSigner({ sign: () => ({ serialized: '0x01' }) });

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const accountMock = await helper.newAccount('$AccountMock', ['Account', '1']);
  await accountMock.deploy();

  // ERC-4337 paymaster signer
  const signer = new NonNativeSigner({ sign: () => ({ serialized: '0x01' }) });

  // ERC-4337 paymaster
  const mock = await ethers.deployContract('$PaymasterCoreMock');

  const signUserOp = async userOp => {
    userOp.signature = await accountSigner.signMessage(userOp.hash());
    return userOp;
  };

  const paymasterSignUserOp = async (userOp, validAfter, validUntil) => {
    const signature = await signer.signMessage(userOp.hash());
    userOp.paymasterData = ethers.solidityPacked(['bool', 'uint48', 'uint48'], [signature, validAfter, validUntil]);
    return userOp;
  };

  return {
    depositor,
    staker,
    receiver,
    target,
    accountMock,
    mock,
    signUserOp,
    paymasterSignUserOp,
    ...env,
  };
}

describe('PaymasterCore', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikePaymaster();
});
