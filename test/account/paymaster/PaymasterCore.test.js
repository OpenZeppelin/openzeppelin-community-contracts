const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { PackedUserOperation, UserOperationRequest } = require('../../helpers/eip712-types');
const { ERC4337Helper } = require('../../helpers/erc4337');

const { shouldBehaveLikePaymaster } = require('./Paymaster.behavior');

for (const [name, opts] of Object.entries({
  PaymasterCore: { postOp: true },
  PaymasterCoreContextNoPostOp: { postOp: false },
})) {
  async function fixture() {
    // EOAs and environment
    const [admin, receiver, other] = await ethers.getSigners();
    const target = await ethers.deployContract('CallReceiverMockExtended');

    // signers
    const accountSigner = ethers.Wallet.createRandom();
    const paymasterSigner = ethers.Wallet.createRandom();

    // ERC-4337 account
    const helper = new ERC4337Helper();
    const env = await helper.wait();
    const account = await helper.newAccount('$AccountECDSAMock', ['AccountECDSA', '1', accountSigner]);
    await account.deploy();

    // ERC-4337 paymaster
    const paymaster = await ethers.deployContract(`$${name}Mock`, ['MyPaymasterECDSASigner', '1', admin]);
    await paymaster.$_setSigner(paymasterSigner);

    const signUserOp = userOp =>
      accountSigner
        .signTypedData(
          {
            name: 'AccountECDSA',
            version: '1',
            chainId: env.chainId,
            verifyingContract: account.target,
          },
          { PackedUserOperation },
          userOp.packed,
        )
        .then(signature => Object.assign(userOp, { signature }));

    const paymasterSignUserOp = (userOp, validAfter, validUntil) =>
      paymasterSigner
        .signTypedData(
          {
            name: 'MyPaymasterECDSASigner',
            version: '1',
            chainId: env.chainId,
            verifyingContract: paymaster.target,
          },
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
      admin,
      receiver,
      other,
      target,
      account,
      paymaster,
      signUserOp,
      paymasterSignUserOp,
      ...env,
    };
  }

  describe(name, function () {
    beforeEach(async function () {
      Object.assign(this, await loadFixture(fixture));
    });

    shouldBehaveLikePaymaster(opts);
  });
}
