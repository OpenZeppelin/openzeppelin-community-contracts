const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { shouldBehaveLikePaymaster } = require('./Paymaster.behavior');
const { ERC4337Helper } = require('../../helpers/erc4337');
const { NonNativeSigner } = require('../../helpers/signers');
const { UserOperationRequest } = require('../../helpers/eip712-types');

async function fixture() {
  // EOAs and environment
  const [depositor, staker, receiver, other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-4337 signer
  const accountSigner = new NonNativeSigner({ sign: () => ({ serialized: '0x01' }) });

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const accountMock = await helper.newAccount('$AccountMock', ['Account', '1']);
  await accountMock.deploy();

  // ERC-4337 paymaster signer
  const signer = ethers.Wallet.createRandom();

  // ERC-4337 paymaster
  const mock = await ethers.deployContract('$PaymasterSignerECDSAMock', [signer]);

  const domain = {
    name: 'MyPaymasterECDSASigner',
    version: '1',
    chainId: env.chainId,
    verifyingContract: mock.target,
  };

  const signUserOp = async userOp => {
    userOp.signature = await accountSigner.signMessage(userOp.hash());
    return userOp;
  };

  const paymasterSignUserOp = async (userOp, validAfter, validUntil) =>
    signer
      .signTypedData(
        domain,
        { UserOperationRequest },
        {
          ...userOp.packed,
          paymasterVerificationGasLimit: userOp.paymasterVerificationGasLimit,
          paymasterPostOpGasLimit: userOp.paymasterPostOpGasLimit,
          validAfter,
          validUntil,
        },
      )
      .then(signature =>
        Object.assign(userOp, {
          paymasterData: ethers.solidityPacked(['uint48', 'uint48', 'bytes'], [validAfter, validUntil, signature]),
        }),
      );

  return {
    depositor,
    staker,
    receiver,
    other,
    target,
    accountMock,
    mock,
    signUserOp,
    paymasterSignUserOp,
    ...env,
  };
}

describe('PaymasterSigner', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikePaymaster();
});
