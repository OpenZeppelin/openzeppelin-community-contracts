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

  describe('pays with ERC-20 tokens', function () {
    beforeEach(async function () {
      await this.paymaster.deposit({ value });

      this.userOp ??= {};
      this.userOp.paymaster = this.paymaster;
    });

    it('from account', async function () {
      // fund account
      await this.token.$_mint(this.account, value);
      await this.token.$_approve(this.account, this.paymaster, ethers.MaxUint256);

      this.extraCalls = [];
      this.withGuarantor = false;
      this.guarantorPays = false;
      this.tokenMovements = [
        { account: this.account, factor: -1n },
        { account: this.paymaster, factor: 1n },
      ];
    });

    it('from account, with guarantor refund', async function () {
      // fund guarantor. account has no asset to pay for at the beginning of the transaction, but will get them during execution.
      await this.token.$_mint(this.guarantor, value);
      await this.token.$_approve(this.guarantor, this.paymaster, ethers.MaxUint256);

      this.extraCalls = [
        { target: this.token, data: this.token.interface.encodeFunctionData('$_mint', [this.account.target, value]) },
        {
          target: this.token,
          data: this.token.interface.encodeFunctionData('approve', [this.paymaster.target, ethers.MaxUint256]),
        },
      ];
      this.withGuarantor = true;
      this.guarantorPays = false;
      this.tokenMovements = [
        { account: this.account, factor: -1n, offset: value },
        { account: this.guarantor, factor: 0n },
        { account: this.paymaster, factor: 1n },
      ];
    });

    it('from account, with guarantor refund (cold storage)', async function () {
      // fund guarantor and account beforeend. All balances and allowances are cold, making it the worst cas for postOp gas costs
      await this.token.$_mint(this.account, value);
      await this.token.$_mint(this.guarantor, value);
      await this.token.$_approve(this.account, this.paymaster, ethers.MaxUint256);
      await this.token.$_approve(this.guarantor, this.paymaster, ethers.MaxUint256);

      this.extraCalls = [];
      this.withGuarantor = true;
      this.guarantorPays = false;
      this.tokenMovements = [
        { account: this.account, factor: -1n },
        { account: this.guarantor, factor: 0n },
        { account: this.paymaster, factor: 1n },
      ];
    });

    it('from guarantor, when account fails to pay', async function () {
      // fund guarantor. account has no asset to pay for at the beginning of the transaction, and will not get them. guarantor ends up covering the cost.
      await this.token.$_mint(this.guarantor, value);
      await this.token.$_approve(this.guarantor, this.paymaster, ethers.MaxUint256);

      this.extraCalls = [];
      this.withGuarantor = true;
      this.guarantorPays = true;
      this.tokenMovements = [
        { account: this.account, factor: 0n },
        { account: this.guarantor, factor: -1n },
        { account: this.paymaster, factor: 1n },
      ];
    });

    afterEach(async function () {
      const signedUserOp = await this.account
        // prepare user operation, with paymaster data
        .createUserOp({
          ...this.userOp,
          callData: this.account.interface.encodeFunctionData('execute', [
            encodeMode({ callType: CALL_TYPE_BATCH }),
            encodeBatch(...this.extraCalls, {
              target: this.target,
              data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
            }),
          ]),
          paymasterData: ethers.solidityPacked(
            ['address', 'uint48', 'uint48', 'uint256', 'address'],
            [this.token.target, 0n, 0n, 2e6, this.withGuarantor ? this.guarantor.address : ethers.ZeroAddress],
          ),
        })
        // sign it
        .then(op => this.signUserOp(op));

      // send it to the entrypoint
      const txPromise = entrypoint.handleOps([signedUserOp.packed], this.receiver);

      // check main events (target call and sponsoring)
      await expect(txPromise)
        .to.emit(this.paymaster, 'UserOperationSponsored')
        .withArgs(
          signedUserOp.hash(),
          this.account,
          this.withGuarantor ? this.guarantor.address : ethers.ZeroAddress,
          anyValue,
          2e6,
          this.guarantorPays,
        )
        .to.emit(this.target, 'MockFunctionCalledExtra')
        .withArgs(this.account, 0n);

      // parse logs:
      // - get tokenAmount repaid for the paymaster event
      // - get the actual gas cost from the entrypoint event
      const { logs } = await txPromise.then(tx => tx.wait());
      const { tokenAmount } = logs.map(ev => this.paymaster.interface.parseLog(ev)).find(Boolean).args;
      const { actualGasCost } = logs.find(ev => ev.fragment?.name == 'UserOperationEvent').args;
      // check token balances moved as expected
      await expect(txPromise).to.changeTokenBalances(
        this.token,
        this.tokenMovements.map(({ account }) => account),
        this.tokenMovements.map(({ factor = 0n, offset = 0n }) => offset + tokenAmount * factor),
      );
      // check that ether moved as expected
      await expect(txPromise).to.changeEtherBalances([entrypoint, this.receiver], [-actualGasCost, actualGasCost]);

      // check token cost is within the expected values
      // skip gas consumption tests when running coverage (significantly affects the postOp costs)
      if (!process.env.COVERAGE) {
        expect(tokenAmount)
          .to.be.greaterThan(actualGasCost * 2n)
          .to.be.lessThan((actualGasCost * 2n * 110n) / 100n); // covers costs with no more than 10% overcost
      }
    });
  });

  describe('withdraw ERC-20 tokens', function () {
    beforeEach(async function () {
      await this.token.$_mint(this.paymaster, value);
    });

    it('withdraw some token', async function () {
      await expect(
        this.paymaster.connect(this.admin).withdrawTokens(this.token, this.receiver, 10n),
      ).to.changeTokenBalances(this.token, [this.paymaster, this.receiver], [-10n, 10n]);
    });

    it('withdraw all token', async function () {
      await expect(
        this.paymaster.connect(this.admin).withdrawTokens(this.token, this.receiver, ethers.MaxUint256),
      ).to.changeTokenBalances(this.token, [this.paymaster, this.receiver], [-value, value]);
    });

    it('only admin can withdraw', async function () {
      await expect(this.paymaster.connect(this.other).withdrawTokens(this.token, this.receiver, 10n)).to.be.reverted;
    });
  });
});
