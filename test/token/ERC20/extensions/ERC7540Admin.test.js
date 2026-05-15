const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const {
  shouldBehaveLikeERC7540Operator,
  shouldBehaveLikeERC7540Deposit,
  shouldBehaveLikeERC7540Redeem,
} = require('./ERC7540.behavior');
const { shouldBehaveLikeERC7575 } = require('./ERC7575.behavior');

const name = 'Vault Shares';
const symbol = 'vSHR';
const tokenName = 'Asset Token';
const tokenSymbol = 'AST';

describe('ERC7540Admin', function () {
  for (const withTmpHolder of [false, true]) {
    describe(withTmpHolder ? 'With a temporary share holder' : 'With direct share operations', function () {
      async function fixture() {
        const token = await ethers.deployContract('$ERC20', [tokenName, tokenSymbol]);
        const mock = await ethers.deployContract('$ERC7540AdminMock', [
          name,
          symbol,
          token,
          withTmpHolder ? '0x000000000000000000000000000000000000dead' : ethers.ZeroAddress,
        ]);
        return { token, mock };
      }

      beforeEach(async function () {
        Object.assign(this, await loadFixture(fixture));

        this.getRequestId = () => 0n;
        this.fulfillDeposit = (requestId, assets, shares, controller) =>
          this.mock.$_fulfillDeposit(assets, shares, controller);
        this.fulfillRedeem = (requestId, assets, shares, controller) =>
          this.mock.$_fulfillRedeem(shares, assets, controller);
      });

      describe('metadata', function () {
        it('token', async function () {
          await expect(this.mock.asset()).to.eventually.equal(this.token);
          await expect(this.mock.vault(this.token)).to.eventually.equal(this.mock);
          await expect(this.mock.vault(this.mock)).to.eventually.equal(ethers.ZeroAddress);
        });

        it('name, symbol, decimals', async function () {
          await expect(this.mock.name()).to.eventually.equal(name);
          await expect(this.mock.symbol()).to.eventually.equal(symbol);
          await expect(this.mock.decimals()).to.eventually.equal(18n);
        });

        it('reports async deposit and redeem', async function () {
          await expect(this.mock.$_isDepositAsync()).to.eventually.equal(true);
          await expect(this.mock.$_isRedeemAsync()).to.eventually.equal(true);
        });
      });

      shouldBehaveLikeERC7540Operator();
      shouldBehaveLikeERC7540Deposit({ supportCustomFulfill: true, withTmpHolder });
      shouldBehaveLikeERC7540Redeem({ supportCustomFulfill: true, withTmpHolder });
      shouldBehaveLikeERC7575();

      describe('multiple partial claims', function () {
        it('deposit flow - finish with a deposit', async function () {
          const [, user] = await ethers.getSigners();
          await this.token.$_mint(user, 1000n);
          await this.token.connect(user).approve(this.mock, ethers.MaxUint256);

          await expect(this.mock.pendingDepositRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(0n);
          await expect(this.mock.maxMint(user)).to.eventually.equal(0n);
          await expect(this.mock.balanceOf(user)).to.eventually.equal(0n);

          await this.mock.connect(user).requestDeposit(100n, user, user);

          await expect(this.mock.pendingDepositRequest(0n, user)).to.eventually.equal(100n);
          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(0n);
          await expect(this.mock.maxMint(user)).to.eventually.equal(0n);
          await expect(this.mock.balanceOf(user)).to.eventually.equal(0n);

          await this.fulfillDeposit(0n, 17n, 42n, user);

          await expect(this.mock.pendingDepositRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(17n);
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(17n);
          await expect(this.mock.maxMint(user)).to.eventually.equal(42n);
          await expect(this.mock.balanceOf(user)).to.eventually.equal(0n);

          await this.mock.connect(user).deposit(5n, user); // 5 assets => 12 shares

          await expect(this.mock.pendingDepositRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(12n); // 17 - 5
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(12n); // 17 - 5
          await expect(this.mock.maxMint(user)).to.eventually.equal(30n); // 42 - 12
          await expect(this.mock.balanceOf(user)).to.eventually.equal(12n);

          await this.mock.connect(user).mint(8n, user); // 8 shares => 4 assets

          await expect(this.mock.pendingDepositRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(8n); // 17 - 5 - 4
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(8n); // 17 - 5 - 4
          await expect(this.mock.maxMint(user)).to.eventually.equal(22n); // 42 - 12 - 8
          await expect(this.mock.balanceOf(user)).to.eventually.equal(20n);

          await this.mock.connect(user).deposit(this.mock.maxDeposit(user), user); // should mint all the rest

          await expect(this.mock.pendingDepositRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(0n);
          await expect(this.mock.maxMint(user)).to.eventually.equal(0n);
          await expect(this.mock.balanceOf(user)).to.eventually.equal(42n);
        });

        it('deposit flow - finish with a mint', async function () {
          const [, user] = await ethers.getSigners();
          await this.token.$_mint(user, 1000n);
          await this.token.connect(user).approve(this.mock, ethers.MaxUint256);

          await expect(this.mock.pendingDepositRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(0n);
          await expect(this.mock.maxMint(user)).to.eventually.equal(0n);
          await expect(this.mock.balanceOf(user)).to.eventually.equal(0n);

          await this.mock.connect(user).requestDeposit(100n, user, user);

          await expect(this.mock.pendingDepositRequest(0n, user)).to.eventually.equal(100n);
          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(0n);
          await expect(this.mock.maxMint(user)).to.eventually.equal(0n);
          await expect(this.mock.balanceOf(user)).to.eventually.equal(0n);

          await this.fulfillDeposit(0n, 17n, 42n, user);

          await expect(this.mock.pendingDepositRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(17n);
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(17n);
          await expect(this.mock.maxMint(user)).to.eventually.equal(42n);
          await expect(this.mock.balanceOf(user)).to.eventually.equal(0n);

          await this.mock.connect(user).mint(8n, user); // 8 shares => 4 assets

          await expect(this.mock.pendingDepositRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(13n); // 17 - 4
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(13n); // 17 - 4
          await expect(this.mock.maxMint(user)).to.eventually.equal(34n); // 42 - 8
          await expect(this.mock.balanceOf(user)).to.eventually.equal(8n);

          await this.mock.connect(user).deposit(5n, user); // 5 assets => 13 shares

          await expect(this.mock.pendingDepositRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(8n); // 17 - 4 - 5
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(8n); // 17 - 4 - 5
          await expect(this.mock.maxMint(user)).to.eventually.equal(21n); // 42 - 8 - 13
          await expect(this.mock.balanceOf(user)).to.eventually.equal(21n);

          await this.mock.connect(user).mint(this.mock.maxMint(user), user); // should mint all the rest

          await expect(this.mock.pendingDepositRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(0n);
          await expect(this.mock.maxMint(user)).to.eventually.equal(0n);
          await expect(this.mock.balanceOf(user)).to.eventually.equal(42n);
        });

        it('redeem flow - finish with a redeem', async function () {
          const [, user] = await ethers.getSigners();
          await this.token.$_mint(this.mock, 1000n);
          await this.mock.$_mint(user, 1000n);

          await expect(this.mock.pendingRedeemRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(0n);
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(0n);
          await expect(this.token.balanceOf(user)).to.eventually.equal(0n);

          await this.mock.connect(user).requestRedeem(100n, user, user);

          await expect(this.mock.pendingRedeemRequest(0n, user)).to.eventually.equal(100n);
          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(0n);
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(0n);
          await expect(this.token.balanceOf(user)).to.eventually.equal(0n);

          await this.fulfillRedeem(0n, 42n, 17n, user);

          await expect(this.mock.pendingRedeemRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(17n);
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(17n);
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(42n);
          await expect(this.token.balanceOf(user)).to.eventually.equal(0n);

          await this.mock.connect(user).redeem(5n, user, user); // 5 shares => 12 assets

          await expect(this.mock.pendingRedeemRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(12n); // 17 - 5
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(12n); // 17 - 5
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(30n); // 42 - 12
          await expect(this.token.balanceOf(user)).to.eventually.equal(12n);

          await this.mock.connect(user).withdraw(8n, user, user); // 8 assets => 4 shares

          await expect(this.mock.pendingRedeemRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(8n); // 17 - 5 - 4
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(8n); // 17 - 5 - 4
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(22n); // 42 - 12 - 8
          await expect(this.token.balanceOf(user)).to.eventually.equal(20n);

          await this.mock.connect(user).redeem(this.mock.maxRedeem(user), user, user); // should mint all the rest

          await expect(this.mock.pendingRedeemRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(0n);
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(0n);
          await expect(this.token.balanceOf(user)).to.eventually.equal(42n);
        });

        it('redeem flow - finish with a withdraw', async function () {
          const [, user] = await ethers.getSigners();
          await this.token.$_mint(this.mock, 1000n);
          await this.mock.$_mint(user, 1000n);

          await expect(this.mock.pendingRedeemRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(0n);
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(0n);
          await expect(this.token.balanceOf(user)).to.eventually.equal(0n);

          await this.mock.connect(user).requestRedeem(100n, user, user);

          await expect(this.mock.pendingRedeemRequest(0n, user)).to.eventually.equal(100n);
          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(0n);
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(0n);
          await expect(this.token.balanceOf(user)).to.eventually.equal(0n);

          await this.fulfillRedeem(0n, 42n, 17n, user);

          await expect(this.mock.pendingRedeemRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(17n);
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(17n);
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(42n);
          await expect(this.token.balanceOf(user)).to.eventually.equal(0n);

          await this.mock.connect(user).withdraw(8n, user, user); // 8 assets => 4 shares

          await expect(this.mock.pendingRedeemRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(13n); // 17 - 4
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(13n); // 17 - 4
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(34n); // 42 - 8
          await expect(this.token.balanceOf(user)).to.eventually.equal(8n);

          await this.mock.connect(user).redeem(5n, user, user); // 5 shares => 13 assets

          await expect(this.mock.pendingRedeemRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(8n); // 17 - 4 - 5
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(8n); // 17 - 4 - 5
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(21n); // 42 - 8 - 13
          await expect(this.token.balanceOf(user)).to.eventually.equal(21n);

          await this.mock.connect(user).withdraw(this.mock.maxWithdraw(user), user, user); // should mint all the rest

          await expect(this.mock.pendingRedeemRequest(0n, user)).to.eventually.equal(83n);
          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(0n);
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(0n);
          await expect(this.token.balanceOf(user)).to.eventually.equal(42n);
        });
      });

      describe('rounding corner cases', function () {
        it('deposit flow - rounding shares to 0 and deposit', async function () {
          const [, user] = await ethers.getSigners();
          await this.token.$_mint(user, 1000n);
          await this.token.connect(user).approve(this.mock, ethers.MaxUint256);

          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(0n);
          await expect(this.mock.maxMint(user)).to.eventually.equal(0n);
          await expect(this.mock.balanceOf(user)).to.eventually.equal(0n);

          await this.mock.connect(user).requestDeposit(100n, user, user);
          await this.fulfillDeposit(0n, 1n, 100n, user);

          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(1n);
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(1n);
          await expect(this.mock.maxMint(user)).to.eventually.equal(100n);
          await expect(this.mock.balanceOf(user)).to.eventually.equal(0n);

          await this.mock.connect(user).mint(1n, user); // 1 share => 1 asset

          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(0n);
          await expect(this.mock.maxMint(user)).to.eventually.equal(99n);
          await expect(this.mock.balanceOf(user)).to.eventually.equal(1n);

          await this.mock.connect(user).deposit(0n, user); // 0 assets => 99 shares

          await expect(this.mock.claimableDepositRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxDeposit(user)).to.eventually.equal(0n);
          await expect(this.mock.maxMint(user)).to.eventually.equal(0n);
          await expect(this.mock.balanceOf(user)).to.eventually.equal(100n);
        });

        it('redeem flow - rounding shares to 0 and redeem', async function () {
          const [, user] = await ethers.getSigners();
          await this.token.$_mint(this.mock, 1000n);
          await this.mock.$_mint(user, 1000n);

          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(0n);
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(0n);
          await expect(this.token.balanceOf(user)).to.eventually.equal(0n);

          await this.mock.connect(user).requestRedeem(100n, user, user);
          await this.fulfillRedeem(0n, 100n, 1n, user);

          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(1n);
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(1n);
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(100n);
          await expect(this.token.balanceOf(user)).to.eventually.equal(0n);

          await this.mock.connect(user).withdraw(1n, user, user); // 1 assets => 1 shares

          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(0n);
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(99n);
          await expect(this.token.balanceOf(user)).to.eventually.equal(1n);

          await this.mock.connect(user).redeem(0n, user, user); // 0 shares => 99 assets

          await expect(this.mock.claimableRedeemRequest(0n, user)).to.eventually.equal(0n);
          await expect(this.mock.maxRedeem(user)).to.eventually.equal(0n);
          await expect(this.mock.maxWithdraw(user)).to.eventually.equal(0n);
          await expect(this.token.balanceOf(user)).to.eventually.equal(100n);
        });
      });
    });
  }
});
