const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const time = require('@openzeppelin/contracts/test/helpers/time');
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
const delay = 3600n;

async function fixture() {
  const token = await ethers.deployContract('$ERC20', [tokenName, tokenSymbol]);
  const mock = await ethers.deployContract('$ERC7540DelayMock', [name, symbol, token]);
  return { token, mock };
}

describe('ERC7540Delay', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));

    this.getRequestId = tx => time.clockFromReceipt.timestamp(tx).then(timestamp => timestamp + delay);
    this.fulfillDeposit = requestId => time.increaseTo.timestamp(requestId);
    this.fulfillRedeem = requestId => time.increaseTo.timestamp(requestId);
  });

  describe('sanity', function () {
    it('construction revert if share origin is not address(0)', async function () {
      const factory = await ethers.getContractFactory('$ERC7540DelayShareOriginMock');
      await expect(
        ethers.deployContract('$ERC7540DelayShareOriginMock', [name, symbol, this.token]),
      ).to.be.revertedWithCustomError(factory, 'ERC7540DelayInvalidDepositShareOrigin');
    });

    it('construction revert if share destination is not address(0)', async function () {
      const factory = await ethers.getContractFactory('$ERC7540DelayShareDestinationMock');
      await expect(
        ethers.deployContract('$ERC7540DelayShareDestinationMock', [name, symbol, this.token]),
      ).to.be.revertedWithCustomError(factory, 'ERC7540DelayInvalidRedeemShareDestination');
    });
  });

  describe('metadata', function () {
    it('token', async function () {
      await expect(this.mock.asset()).to.eventually.equal(this.token);
    });

    it('name, symbol, decimals', async function () {
      await expect(this.mock.name()).to.eventually.equal(name);
      await expect(this.mock.symbol()).to.eventually.equal(symbol);
      await expect(this.mock.decimals()).to.eventually.equal(18n);
    });

    it('reports default delay', async function () {
      await expect(this.mock.depositDelay(ethers.ZeroAddress)).to.eventually.equal(delay);
      await expect(this.mock.redeemDelay(ethers.ZeroAddress)).to.eventually.equal(delay);
    });

    it('reports async deposit and redeem', async function () {
      await expect(this.mock.$_isDepositAsync()).to.eventually.equal(true);
      await expect(this.mock.$_isRedeemAsync()).to.eventually.equal(true);
    });
  });

  shouldBehaveLikeERC7540Operator();
  shouldBehaveLikeERC7540Deposit({ supportCustomFulfill: false });
  shouldBehaveLikeERC7540Redeem({ supportCustomFulfill: false });
  shouldBehaveLikeERC7575();

  describe('multiple requests and partial claims', function () {
    it('deposit flow', async function () {
      const expectPendingClaimable = (requestId, account, pending, claimable) =>
        Promise.all([
          expect(this.mock.pendingDepositRequest(requestId, user)).to.eventually.equal(pending),
          expect(this.mock.claimableDepositRequest(requestId, user)).to.eventually.equal(claimable),
        ]);

      const [user] = await ethers.getSigners();
      await this.token.$_mint(user, 1000n);
      await this.token.connect(user).approve(this.mock, ethers.MaxUint256);

      const timepoint = (await time.clock.timestamp()) + 100n;

      await expectPendingClaimable(timepoint + delay, user, 0n, 0n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 0n, 0n);
      await expect(this.mock.maxDeposit(user)).to.eventually.equal(0n);

      await time.increaseTo.timestamp(timepoint, false);
      await this.mock.connect(user).requestDeposit(100n, user, user);

      await expectPendingClaimable(timepoint + delay, user, 100n, 0n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 0n, 0n);
      await expect(this.mock.maxDeposit(user)).to.eventually.equal(0n);

      await time.increaseTo.timestamp(timepoint + 10n, false);
      await this.mock.connect(user).requestDeposit(200n, user, user);

      await expectPendingClaimable(timepoint + delay, user, 100n, 0n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 200n, 0n);
      await expect(this.mock.maxDeposit(user)).to.eventually.equal(0n);

      await time.increaseTo.timestamp(timepoint + delay);

      await expectPendingClaimable(timepoint + delay, user, 0n, 100n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 200n, 0n);
      await expect(this.mock.maxDeposit(user)).to.eventually.equal(100n);

      await this.mock.deposit(50n, user);

      await expectPendingClaimable(timepoint + delay, user, 0n, 50n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 200n, 0n);
      await expect(this.mock.maxDeposit(user)).to.eventually.equal(50n);

      await time.increaseTo.timestamp(timepoint + delay + 10n);

      await expectPendingClaimable(timepoint + delay, user, 0n, 50n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 0n, 200n);
      await expect(this.mock.maxDeposit(user)).to.eventually.equal(250n);

      await this.mock.deposit(100n, user);

      await expectPendingClaimable(timepoint + delay, user, 0n, 0n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 0n, 150n);
      await expect(this.mock.maxDeposit(user)).to.eventually.equal(150n);
    });

    it('redeem flow', async function () {
      const expectPendingClaimable = (requestId, account, pending, claimable) =>
        Promise.all([
          expect(this.mock.pendingRedeemRequest(requestId, user)).to.eventually.equal(pending),
          expect(this.mock.claimableRedeemRequest(requestId, user)).to.eventually.equal(claimable),
        ]);

      const [user] = await ethers.getSigners();
      await this.token.$_mint(this.mock, 1000n);
      await this.mock.$_mint(user, 1000n);

      const timepoint = (await time.clock.timestamp()) + 100n;

      await expectPendingClaimable(timepoint + delay, user, 0n, 0n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 0n, 0n);
      await expect(this.mock.maxRedeem(user)).to.eventually.equal(0n);

      await time.increaseTo.timestamp(timepoint, false);
      await this.mock.connect(user).requestRedeem(100n, user, user);

      await expectPendingClaimable(timepoint + delay, user, 100n, 0n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 0n, 0n);
      await expect(this.mock.maxRedeem(user)).to.eventually.equal(0n);

      await time.increaseTo.timestamp(timepoint + 10n, false);
      await this.mock.connect(user).requestRedeem(200n, user, user);

      await expectPendingClaimable(timepoint + delay, user, 100n, 0n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 200n, 0n);
      await expect(this.mock.maxRedeem(user)).to.eventually.equal(0n);

      await time.increaseTo.timestamp(timepoint + delay);

      await expectPendingClaimable(timepoint + delay, user, 0n, 100n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 200n, 0n);
      await expect(this.mock.maxRedeem(user)).to.eventually.equal(100n);

      await this.mock.redeem(50n, user, user);

      await expectPendingClaimable(timepoint + delay, user, 0n, 50n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 200n, 0n);
      await expect(this.mock.maxRedeem(user)).to.eventually.equal(50n);

      await time.increaseTo.timestamp(timepoint + delay + 10n);

      await expectPendingClaimable(timepoint + delay, user, 0n, 50n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 0n, 200n);
      await expect(this.mock.maxRedeem(user)).to.eventually.equal(250n);

      await this.mock.redeem(100n, user, user);

      await expectPendingClaimable(timepoint + delay, user, 0n, 0n);
      await expectPendingClaimable(timepoint + delay + 10n, user, 0n, 150n);
      await expect(this.mock.maxRedeem(user)).to.eventually.equal(150n);
    });
  });
});
