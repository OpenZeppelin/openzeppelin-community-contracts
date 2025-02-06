const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');

const { encodeBatch, encodeMode, CALL_TYPE_BATCH } = require('@openzeppelin/contracts/test/helpers/erc7579');
const { PackedUserOperation } = require('../../helpers/eip712-types');
const { ERC4337Helper } = require('../../helpers/erc4337');

const { shouldBehaveLikePaymaster } = require('./Paymaster.behavior');

const value = ethers.parseEther('1');

async function fixture() {
  // EOAs and environment
  const [admin, receiver, guarantor, other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');
  const token = await ethers.deployContract('$ERC20Mock', ['Name', 'Symbol']);

  // signers
  const accountSigner = ethers.Wallet.createRandom();

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const account = await helper.newAccount('$AccountECDSAMock', ['AccountECDSA', '1', accountSigner]);
  await account.deploy();

  // ERC-4337 paymaster
  const paymaster = await ethers.deployContract(`$PaymasterERC20Mock`, [admin]);

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

  return {
    admin,
    receiver,
    guarantor,
    other,
    target,
    token,
    account,
    paymaster,
    signUserOp,
    ...env,
  };
}

describe('PaymasterERC20', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('core paymaster behavior', async function () {
    beforeEach(async function () {
      await this.token.$_mint(this.account, value);
      await this.token.$_approve(this.account, this.paymaster, ethers.MaxUint256);

      // use token
      this.paymasterSignUserOp = (userOp, validAfter, validUntil) =>
        Object.assign(userOp, {
          paymasterData: ethers.solidityPacked(
            ['address', 'uint48', 'uint48', 'uint256', 'address'],
            [this.token.target, validAfter, validUntil, 1e6, ethers.ZeroAddress],
          ),
        });

      // use invalid token contract
      this.paymasterSignUserOpInvalid = (userOp, validAfter, validUntil) =>
        Object.assign(userOp, {
          paymasterData: ethers.solidityPacked(
            ['address', 'uint48', 'uint48', 'uint256', 'address'],
            [this.other.address, validAfter, validUntil, 1e6, ethers.ZeroAddress],
          ),
        });
    });

    shouldBehaveLikePaymaster({ timeRange: true });
  });

  describe.only('moves ERC-20 balances', function () {
    beforeEach(async function () {
      await this.paymaster.deposit({ value });
    });

    it('from account', async function () {
      // fund account
      await this.token.$_mint(this.account, value);
      await this.token.$_approve(this.account, this.paymaster, ethers.MaxUint256);

      // prepare user operation
      const signedUserOp = await this.account
        .createUserOp({
          callData: this.account.interface.encodeFunctionData('execute', [
            encodeMode({ callType: CALL_TYPE_BATCH }),
            encodeBatch({
              target: this.target,
              data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
            }),
          ]),
          paymaster: this.paymaster,
          paymasterData: ethers.solidityPacked(
            ['address', 'uint48', 'uint48', 'uint256', 'address'],
            [this.token.target, 0n, 0n, 2e6, ethers.ZeroAddress],
          ),
        })
        .then(op => this.signUserOp(op));

      // perform operation
      const txPromise = entrypoint.handleOps([signedUserOp.packed], this.receiver);
      await expect(txPromise)
        .to.emit(this.token, 'Transfer')
        .withArgs(this.account, this.paymaster, anyValue)
        .to.emit(this.token, 'Transfer')
        .withArgs(this.paymaster, this.account, anyValue)
        .to.emit(this.paymaster, 'UserOperationSponsored')
        .withArgs(signedUserOp.hash(), this.account, ethers.ZeroAddress, anyValue, 2e6, false)
        .to.emit(this.target, 'MockFunctionCalledExtra')
        .withArgs(this.account, 0n);

      const { logs } = await txPromise.then(tx => tx.wait());
      const actualAmount = this.paymaster.interface.parseLog(logs.find(ev => ev.address == this.paymaster.target))
        .args[3];
      await expect(txPromise).to.changeTokenBalances(
        this.token,
        [this.account, this.paymaster],
        [-actualAmount, actualAmount],
      );
      // amount of ether transferred from entrypoint to receiver (deducted from paymaster's deposit) is approximately `actualAmount / 2`
    });

    it('from account, with guarantor refund', async function () {
      // fund guarantor. account has no asset to pay for at the beginning of the transaction, but will get them during execution.
      await this.token.$_mint(this.guarantor, value);
      await this.token.$_approve(this.guarantor, this.paymaster, ethers.MaxUint256);

      // prepare user operation
      const signedUserOp = await this.account
        .createUserOp({
          callData: this.account.interface.encodeFunctionData('execute', [
            encodeMode({ callType: CALL_TYPE_BATCH }),
            encodeBatch(
              {
                target: this.token,
                data: this.token.interface.encodeFunctionData('$_mint', [this.account.target, value]),
              },
              {
                target: this.token,
                data: this.token.interface.encodeFunctionData('approve', [this.paymaster.target, ethers.MaxUint256]),
              },
              {
                target: this.target,
                data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
              },
            ),
          ]),
          paymaster: this.paymaster,
          paymasterData: ethers.solidityPacked(
            ['address', 'uint48', 'uint48', 'uint256', 'address'],
            [this.token.target, 0n, 0n, 2e6, this.guarantor.address],
          ),
        })
        .then(op => this.signUserOp(op));

      // perform operation
      const txPromise = entrypoint.handleOps([signedUserOp.packed], this.receiver);
      await expect(txPromise)
        .to.emit(this.token, 'Transfer')
        .withArgs(this.guarantor, this.paymaster, anyValue)
        .to.emit(this.token, 'Transfer')
        .withArgs(ethers.ZeroAddress, this.account, value)
        .to.emit(this.token, 'Transfer')
        .withArgs(this.account, this.paymaster, anyValue)
        .to.emit(this.token, 'Transfer')
        .withArgs(this.paymaster, this.guarantor, anyValue)
        .to.emit(this.paymaster, 'UserOperationSponsored')
        .withArgs(signedUserOp.hash(), this.account, this.guarantor, anyValue, 2e6, false)
        .to.emit(this.target, 'MockFunctionCalledExtra')
        .withArgs(this.account, 0n);

      const { logs } = await txPromise.then(tx => tx.wait());
      const actualAmount = this.paymaster.interface.parseLog(logs.find(ev => ev.address == this.paymaster.target))
        .args[3];
      await expect(txPromise).to.changeTokenBalances(
        this.token,
        [this.account, this.guarantor, this.paymaster],
        [value - actualAmount, 0n, actualAmount],
      );
      // amount of ether transferred from entrypoint to receiver (deducted from paymaster's deposit) is approximately `actualAmount / 2`
    });

    it('from guarantor, when account fails to pay', async function () {
      // fund guarantor. account has no asset to pay for at the beginning of the transaction, and will not get them. guarantor ends up covering the cost.
      await this.token.$_mint(this.guarantor, value);
      await this.token.$_approve(this.guarantor, this.paymaster, ethers.MaxUint256);

      // prepare user operation
      const signedUserOp = await this.account
        .createUserOp({
          callData: this.account.interface.encodeFunctionData('execute', [
            encodeMode({ callType: CALL_TYPE_BATCH }),
            encodeBatch({
              target: this.target,
              data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
            }),
          ]),
          paymaster: this.paymaster,
          paymasterData: ethers.solidityPacked(
            ['address', 'uint48', 'uint48', 'uint256', 'address'],
            [this.token.target, 0n, 0n, 2e6, this.guarantor.address],
          ),
        })
        .then(op => this.signUserOp(op));

      // perform operation
      const txPromise = entrypoint.handleOps([signedUserOp.packed], this.receiver);
      await expect(txPromise)
        .to.emit(this.token, 'Transfer')
        .withArgs(this.guarantor, this.paymaster, anyValue)
        .to.emit(this.token, 'Transfer')
        .withArgs(this.paymaster, this.guarantor, anyValue)
        .to.emit(this.paymaster, 'UserOperationSponsored')
        .withArgs(signedUserOp.hash(), this.account, this.guarantor, anyValue, 2e6, true)
        .to.emit(this.target, 'MockFunctionCalledExtra')
        .withArgs(this.account, 0n);

      const { logs } = await txPromise.then(tx => tx.wait());
      const actualAmount = this.paymaster.interface.parseLog(logs.find(ev => ev.address == this.paymaster.target))
        .args[3];
      await expect(txPromise).to.changeTokenBalances(
        this.token,
        [this.account, this.guarantor, this.paymaster],
        [0n, -actualAmount, actualAmount],
      );
      // amount of ether transferred from entrypoint to receiver (deducted from paymaster's deposit) is approximately `actualAmount / 2`
    });
  });
});
