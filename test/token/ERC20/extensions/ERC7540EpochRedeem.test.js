const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const time = require('@openzeppelin/contracts/test/helpers/time');
const { shouldBehaveLikeERC7540Operator, shouldBehaveLikeERC7540Redeem } = require('./ERC7540.behavior');
const { shouldBehaveLikeERC7575 } = require('./ERC7575.behavior');

const name = 'Vault Shares';
const symbol = 'vSHR';
const tokenName = 'Asset Token';
const tokenSymbol = 'AST';
const week = 7n * 24n * 3600n;

async function fixture() {
  const token = await ethers.deployContract('$ERC20', [tokenName, tokenSymbol]);
  const mock = await ethers.deployContract('$ERC7540EpochMock', [name, symbol, token]);
  return { token, mock };
}

// Advances time so that `currentRedeemEpoch() > epochId`. Idempotent: no-op if already past.
async function advancePast(epochId) {
  const now = await time.clock.timestamp();
  const target = (BigInt(epochId) + 1n) * week;
  if (now < target) await time.increaseTo.timestamp(target);
}

describe('ERC7540EpochRedeem', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));

    this.getRequestId = tx => time.clockFromReceipt.timestamp(tx).then(timestamp => timestamp / week);

    this.fulfillDeposit = async (requestId, _assets, shares) => {
      await advancePast(requestId);
      return this.mock.$_fulfillDeposit(requestId, shares);
    };
    this.fulfillRedeem = async (requestId, assets) => {
      await advancePast(requestId);
      return this.mock.$_fulfillRedeem(requestId, assets);
    };
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

    it('reports async deposit and redeem', async function () {
      await expect(this.mock.$_isDepositAsync()).to.eventually.equal(true);
      await expect(this.mock.$_isRedeemAsync()).to.eventually.equal(true);
    });

    it('default epoch matches `block.timestamp / 1 weeks`', async function () {
      const now = await time.clock.timestamp();
      await expect(this.mock.currentRedeemEpoch()).to.eventually.equal(now / week);
    });
  });

  shouldBehaveLikeERC7540Operator();
  shouldBehaveLikeERC7540Redeem({ supportCustomFulfill: false });
  shouldBehaveLikeERC7575();

  describe('epoch state and getters', function () {
    let user;

    beforeEach(async function () {
      [, user] = await ethers.getSigners();
      await this.token.$_mint(this.mock, 1000n);
      await this.mock.$_mint(user, 1000n);
    });

    it('`requestRedeem` returns the current epoch as `requestId`', async function () {
      const tx = await this.mock.connect(user).requestRedeem(100n, user, user);
      const expected = (await time.clockFromReceipt.timestamp(tx)) / week;
      await expect(tx).to.emit(this.mock, 'RedeemRequest').withArgs(user, user, expected, user, 100n);
    });

    it('`totalRedeemShares` / `totalRedeemAssets` reflect storage', async function () {
      const tx = await this.mock.connect(user).requestRedeem(100n, user, user);
      const epochId = await this.getRequestId(tx);

      await expect(this.mock.totalRedeemShares(epochId)).to.eventually.equal(100n);
      await expect(this.mock.totalRedeemAssets(epochId)).to.eventually.equal(0n);

      await advancePast(epochId);
      await this.mock.$_fulfillRedeem(epochId, 42n);

      await expect(this.mock.totalRedeemShares(epochId)).to.eventually.equal(100n);
      await expect(this.mock.totalRedeemAssets(epochId)).to.eventually.equal(42n);
    });

    it('`_convertToRedeemAssets` returns 0 when `totalShares == 0`', async function () {
      // unknown epoch -> totalShares = 0
      await expect(this.mock.$_convertToRedeemAssets(999n, 100n, 0n)).to.eventually.equal(0n);
    });

    it('`_convertToRedeemShares` returns 0 when `totalAssets == 0`', async function () {
      // pending epoch -> totalAssets = 0
      const tx = await this.mock.connect(user).requestRedeem(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await expect(this.mock.$_convertToRedeemShares(epochId, 50n, 0n)).to.eventually.equal(0n);
    });

    it('`_convertToRedeemAssets` applies the locked rate', async function () {
      const tx = await this.mock.connect(user).requestRedeem(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);
      await this.mock.$_fulfillRedeem(epochId, 50n); // rate 1 share = 0.5 assets

      // Floor: floor(40 * 50 / 100) = 20
      await expect(this.mock.$_convertToRedeemAssets(epochId, 40n, 0n)).to.eventually.equal(20n);
      // Ceil: ceil(33 * 50 / 100) = 17
      await expect(this.mock.$_convertToRedeemAssets(epochId, 33n, 1n)).to.eventually.equal(17n);
    });

    it('`_convertToRedeemShares` applies the locked rate', async function () {
      const tx = await this.mock.connect(user).requestRedeem(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);
      await this.mock.$_fulfillRedeem(epochId, 50n);

      // Floor: floor(10 * 100 / 50) = 20
      await expect(this.mock.$_convertToRedeemShares(epochId, 10n, 0n)).to.eventually.equal(20n);
      // Ceil: ceil(11 * 100 / 50) = 22
      await expect(this.mock.$_convertToRedeemShares(epochId, 11n, 1n)).to.eventually.equal(22n);
    });

    it('`_pendingAvailableRedeemRequest` masks drained epochs', async function () {
      const tx = await this.mock.connect(user).requestRedeem(100n, user, user);
      const epochId = await this.getRequestId(tx);

      // Pending: totalShares > 0 -> returns requests[c]
      await expect(this.mock.$_pendingAvailableRedeemRequest(epochId, user)).to.eventually.equal(100n);

      // Unknown epoch: totalShares == 0 -> returns 0
      await expect(this.mock.$_pendingAvailableRedeemRequest(999n, user)).to.eventually.equal(0n);
    });

    it('pending vs. claimable sentinel distinguishes states', async function () {
      const tx = await this.mock.connect(user).requestRedeem(100n, user, user);
      const epochId = await this.getRequestId(tx);

      // Pending state
      await expect(this.mock.pendingRedeemRequest(epochId, user)).to.eventually.equal(100n);
      await expect(this.mock.claimableRedeemRequest(epochId, user)).to.eventually.equal(0n);

      await advancePast(epochId);
      await this.mock.$_fulfillRedeem(epochId, 42n);

      // Claimable state
      await expect(this.mock.pendingRedeemRequest(epochId, user)).to.eventually.equal(0n);
      await expect(this.mock.claimableRedeemRequest(epochId, user)).to.eventually.equal(100n);

      // Consume the full claim
      await this.mock.connect(user).redeem(100n, user, user);

      // Fully-claimed (drained): totalShares and totalAssets both reach 0
      await expect(this.mock.totalRedeemShares(epochId)).to.eventually.equal(0n);
      await expect(this.mock.totalRedeemAssets(epochId)).to.eventually.equal(0n);
      await expect(this.mock.pendingRedeemRequest(epochId, user)).to.eventually.equal(0n);
      await expect(this.mock.claimableRedeemRequest(epochId, user)).to.eventually.equal(0n);
      await expect(this.mock.maxWithdraw(user)).to.eventually.equal(0n);
      await expect(this.mock.maxRedeem(user)).to.eventually.equal(0n);
    });
  });

  describe('_fulfillRedeem', function () {
    let user;

    beforeEach(async function () {
      [, user] = await ethers.getSigners();
      await this.token.$_mint(this.mock, 1000n);
      await this.mock.$_mint(user, 1000n);
    });

    it('emits `ERC7540EpochRedeemFulfilled` with the locked rate', async function () {
      const tx = await this.mock.connect(user).requestRedeem(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);

      await expect(this.mock.$_fulfillRedeem(epochId, 42n))
        .to.emit(this.mock, 'ERC7540EpochRedeemFulfilled')
        .withArgs(epochId, 100n, 42n);
    });

    it('reverts `TooEarly` when the epoch is still the current one', async function () {
      const tx = await this.mock.connect(user).requestRedeem(100n, user, user);
      const epochId = await this.getRequestId(tx);

      await expect(this.mock.$_fulfillRedeem(epochId, 42n))
        .to.be.revertedWithCustomError(this.mock, 'ERC7540EpochRedeemTooEarly')
        .withArgs(epochId);
    });

    it('reverts `EmptyEpoch` for an epoch with no requests', async function () {
      const current = await this.mock.currentRedeemEpoch();
      await advancePast(current);

      await expect(this.mock.$_fulfillRedeem(current, 42n))
        .to.be.revertedWithCustomError(this.mock, 'ERC7540EpochRedeemEmptyEpoch')
        .withArgs(current);
    });

    it('reverts `AlreadyFulfilled` on a second non-zero fulfill', async function () {
      const tx = await this.mock.connect(user).requestRedeem(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);
      await this.mock.$_fulfillRedeem(epochId, 42n);

      await expect(this.mock.$_fulfillRedeem(epochId, 50n))
        .to.be.revertedWithCustomError(this.mock, 'ERC7540EpochRedeemAlreadyFulfilled')
        .withArgs(epochId);
    });

    it('a 0-asset fulfillment is a no-op and can be recovered by re-fulfilling', async function () {
      const tx = await this.mock.connect(user).requestRedeem(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);

      await this.mock.$_fulfillRedeem(epochId, 0n);

      // State is still "pending" — sentinel hasn't tripped
      await expect(this.mock.totalRedeemAssets(epochId)).to.eventually.equal(0n);
      await expect(this.mock.pendingRedeemRequest(epochId, user)).to.eventually.equal(100n);
      await expect(this.mock.claimableRedeemRequest(epochId, user)).to.eventually.equal(0n);

      await expect(this.mock.$_fulfillRedeem(epochId, 42n))
        .to.emit(this.mock, 'ERC7540EpochRedeemFulfilled')
        .withArgs(epochId, 100n, 42n);
      await expect(this.mock.totalRedeemAssets(epochId)).to.eventually.equal(42n);
      await expect(this.mock.claimableRedeemRequest(epochId, user)).to.eventually.equal(100n);
    });
  });

  describe('multi-epoch flow', function () {
    it('a controller can hold requests across multiple epochs and claim each', async function () {
      const [, user] = await ethers.getSigners();
      await this.token.$_mint(this.mock, 1000n);
      await this.mock.$_mint(user, 1000n);

      const txA = await this.mock.connect(user).requestRedeem(100n, user, user);
      const epochA = await this.getRequestId(txA);

      await time.increaseTo.timestamp((epochA + 1n) * week);
      const txB = await this.mock.connect(user).requestRedeem(50n, user, user);
      const epochB = await this.getRequestId(txB);
      expect(epochB).to.equal(epochA + 1n);

      await advancePast(epochB);
      await this.mock.$_fulfillRedeem(epochA, 200n); // 100 shares -> 200 assets
      await this.mock.$_fulfillRedeem(epochB, 50n); //  50 shares ->  50 assets

      await expect(this.mock.maxRedeem(user)).to.eventually.equal(150n);
      await expect(this.mock.maxWithdraw(user)).to.eventually.equal(250n);

      await this.mock.connect(user).withdraw(100n, user, user);
      await expect(this.token.balanceOf(user)).to.eventually.equal(100n);

      await this.mock.connect(user).withdraw(this.mock.maxWithdraw(user), user, user);
      await expect(this.token.balanceOf(user)).to.eventually.equal(250n);
      await expect(this.mock.maxWithdraw(user)).to.eventually.equal(0n);
    });

    it('multiple controllers in the same epoch share pro-rata', async function () {
      const [, alice, bob, carol] = await ethers.getSigners();
      await this.token.$_mint(this.mock, 1000n);
      for (const u of [alice, bob, carol]) {
        await this.mock.$_mint(u, 1000n);
      }

      const txA = await this.mock.connect(alice).requestRedeem(30n, alice, alice);
      await this.mock.connect(bob).requestRedeem(40n, bob, bob);
      await this.mock.connect(carol).requestRedeem(30n, carol, carol);
      const epochId = await this.getRequestId(txA);

      await expect(this.mock.totalRedeemShares(epochId)).to.eventually.equal(100n);

      await advancePast(epochId);
      await this.mock.$_fulfillRedeem(epochId, 200n); // 100 -> 200, exact rate 1:2

      await expect(this.mock.maxWithdraw(alice)).to.eventually.equal(60n);
      await expect(this.mock.maxWithdraw(bob)).to.eventually.equal(80n);
      await expect(this.mock.maxWithdraw(carol)).to.eventually.equal(60n);

      await this.mock.connect(alice).redeem(30n, alice, alice);
      await this.mock.connect(bob).redeem(40n, bob, bob);
      await this.mock.connect(carol).redeem(30n, carol, carol);

      await expect(this.token.balanceOf(alice)).to.eventually.equal(60n);
      await expect(this.token.balanceOf(bob)).to.eventually.equal(80n);
      await expect(this.token.balanceOf(carol)).to.eventually.equal(60n);

      await expect(this.mock.totalRedeemShares(epochId)).to.eventually.equal(0n);
      await expect(this.mock.totalRedeemAssets(epochId)).to.eventually.equal(0n);
    });
  });

  describe('redeemEpochs', function () {
    let user;

    beforeEach(async function () {
      [, user] = await ethers.getSigners();
      await this.token.$_mint(this.mock, 10000n);
      await this.mock.$_mint(user, 10000n);
    });

    it('returns empty for a controller with no requests', async function () {
      await expect(this.mock.redeemEpochs(user, 0, ethers.MaxUint256)).to.eventually.deep.equal([]);
      await expect(this.mock.redeemEpochs(user, 0, 10)).to.eventually.deep.equal([]);
    });

    it('returns each epoch in queue order (oldest first)', async function () {
      const e0 = await this.mock.currentRedeemEpoch();
      await this.mock.connect(user).requestRedeem(100n, user, user);
      await time.increaseTo.timestamp((e0 + 1n) * week);
      await this.mock.connect(user).requestRedeem(100n, user, user);
      await time.increaseTo.timestamp((e0 + 2n) * week);
      await this.mock.connect(user).requestRedeem(100n, user, user);

      await expect(this.mock.redeemEpochs(user, 0, ethers.MaxUint256)).to.eventually.deep.equal([e0, e0 + 1n, e0 + 2n]);
    });

    it('collapses multiple requests in the same epoch into one entry', async function () {
      const e0 = await this.mock.currentRedeemEpoch();
      await this.mock.connect(user).requestRedeem(50n, user, user);
      await this.mock.connect(user).requestRedeem(50n, user, user);

      await expect(this.mock.redeemEpochs(user, 0, ethers.MaxUint256)).to.eventually.deep.equal([e0]);
    });

    it('pops fully-claimed epochs from the queue', async function () {
      const e0 = await this.mock.currentRedeemEpoch();
      await this.mock.connect(user).requestRedeem(100n, user, user);
      await time.increaseTo.timestamp((e0 + 1n) * week);
      await this.mock.connect(user).requestRedeem(100n, user, user);

      await advancePast(e0 + 1n);
      await this.mock.$_fulfillRedeem(e0, 200n);
      await this.mock.$_fulfillRedeem(e0 + 1n, 200n);

      await expect(this.mock.redeemEpochs(user, 0, ethers.MaxUint256)).to.eventually.deep.equal([e0, e0 + 1n]);

      // Claim the first epoch fully — _consumeClaimableRedeem pops it from the queue
      await this.mock.connect(user).redeem(100n, user, user);
      await expect(this.mock.redeemEpochs(user, 0, ethers.MaxUint256)).to.eventually.deep.equal([e0 + 1n]);
    });

    it('paginates with [start, end)', async function () {
      const e0 = await this.mock.currentRedeemEpoch();
      for (let i = 0; i < 4; i++) {
        await this.mock.connect(user).requestRedeem(10n, user, user);
        await time.increaseTo.timestamp((e0 + BigInt(i + 1)) * week);
      }
      const all = [e0, e0 + 1n, e0 + 2n, e0 + 3n];

      await expect(this.mock.redeemEpochs(user, 0, 4)).to.eventually.deep.equal(all);
      await expect(this.mock.redeemEpochs(user, 1, 3)).to.eventually.deep.equal(all.slice(1, 3));
      await expect(this.mock.redeemEpochs(user, 0, 1)).to.eventually.deep.equal(all.slice(0, 1));
    });

    it('clamps out-of-bound `start` and `end`', async function () {
      const e0 = await this.mock.currentRedeemEpoch();
      await this.mock.connect(user).requestRedeem(100n, user, user);

      // end > length → clamped
      await expect(this.mock.redeemEpochs(user, 0, ethers.MaxUint256)).to.eventually.deep.equal([e0]);
      // start > length → empty after both clamps
      await expect(this.mock.redeemEpochs(user, 10, ethers.MaxUint256)).to.eventually.deep.equal([]);
      // start > end → empty
      await expect(this.mock.redeemEpochs(user, 1, 0)).to.eventually.deep.equal([]);
    });
  });

  describe('queue limit', function () {
    it('enforces `_requestQueueLimit` per controller', async function () {
      const [, user] = await ethers.getSigners();
      await this.token.$_mint(this.mock, 10000n);
      await this.mock.$_mint(user, 10000n);

      let epoch = await this.mock.currentRedeemEpoch();
      for (let i = 0; i < 32; i++) {
        await this.mock.connect(user).requestRedeem(1n, user, user);
        epoch = epoch + 1n;
        await time.increaseTo.timestamp(epoch * week);
      }

      await expect(this.mock.connect(user).requestRedeem(1n, user, user)).to.be.reverted;
    });

    it('multiple requests in the same epoch share one queue slot', async function () {
      const [, user] = await ethers.getSigners();
      await this.token.$_mint(this.mock, 1000n);
      await this.mock.$_mint(user, 1000n);

      for (let i = 0; i < 50; i++) {
        await this.mock.connect(user).requestRedeem(1n, user, user);
      }
      const epochId = await this.mock.currentRedeemEpoch();
      await expect(this.mock.totalRedeemShares(epochId)).to.eventually.equal(50n);
    });
  });

  describe('edge cases', function () {
    it('a 1-asset fulfillment makes withdraw(0) a no-op (per-claim rounding edge)', async function () {
      const [, user] = await ethers.getSigners();
      await this.token.$_mint(this.mock, 1000n);
      await this.mock.$_mint(user, 1000n);

      const tx = await this.mock.connect(user).requestRedeem(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);
      await this.mock.$_fulfillRedeem(epochId, 1n); // 100 shares -> 1 asset

      const before = await this.token.balanceOf(user);
      await this.mock.connect(user).withdraw(0n, user, user);
      await expect(this.token.balanceOf(user)).to.eventually.equal(before);

      // Share-driven `redeem` is the path that can absorb the floor-rounding dust
      await this.mock.connect(user).redeem(100n, user, user);
      await expect(this.token.balanceOf(user)).to.eventually.equal(1n);
    });

    it('saturating sub absorbs ceil/floor excess; drained-state dust is hidden from views', async function () {
      // Pathological tiny-totals scenario to trigger Case A overshoot in the asset-driven
      // path. Uses the internal `$_consumeClaimableWithdraw` to bypass the public
      // `maxWithdraw` guard so we can force the rounding excess that saturating sub absorbs.
      //
      // Setup: r_alice=2, r_bob=3, totalShares=5. Fulfill totalAssets=3.
      //   Alice Case A (assets=2): requested=ceil(2*3/5)=2, batchShares uncapped=floor(2*5/3)=3 (overshoot by 1)
      //   Sat-sub: r_alice 2->0, totalShares 5->2, totalAssets 3->1.
      //   Bob Case B (assets=1): requested=ceil(3*1/2)=2 > assets=1, batchShares=floor(1*2/1)=2.
      //   Sat-sub: r_bob saturates 3->1 (dust), totalShares 2->0, totalAssets 1->0 (drained).
      const [, alice, bob] = await ethers.getSigners();
      await this.token.$_mint(this.mock, 1000n);
      for (const u of [alice, bob]) {
        await this.mock.$_mint(u, 1000n);
      }

      const tx = await this.mock.connect(alice).requestRedeem(2n, alice, alice);
      await this.mock.connect(bob).requestRedeem(3n, bob, bob);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);
      await this.mock.$_fulfillRedeem(epochId, 3n);

      await this.mock.$_consumeClaimableWithdraw(2n, alice);
      await expect(this.mock.totalRedeemShares(epochId)).to.eventually.equal(2n);
      await expect(this.mock.totalRedeemAssets(epochId)).to.eventually.equal(1n);

      await this.mock.$_consumeClaimableWithdraw(1n, bob);
      await expect(this.mock.totalRedeemShares(epochId)).to.eventually.equal(0n);
      await expect(this.mock.totalRedeemAssets(epochId)).to.eventually.equal(0n);

      // The 1-wei dust in bob's slot is invisible through every public view
      await expect(this.mock.pendingRedeemRequest(epochId, bob)).to.eventually.equal(0n);
      await expect(this.mock.claimableRedeemRequest(epochId, bob)).to.eventually.equal(0n);
      await expect(this.mock.maxWithdraw(bob)).to.eventually.equal(0n);
      await expect(this.mock.maxRedeem(bob)).to.eventually.equal(0n);
    });

    it('a fully-drained epoch keeps the {_fulfillRedeem} sentinel intact', async function () {
      const [, user] = await ethers.getSigners();
      await this.token.$_mint(this.mock, 1000n);
      await this.mock.$_mint(user, 1000n);

      const tx = await this.mock.connect(user).requestRedeem(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);
      await this.mock.$_fulfillRedeem(epochId, 42n);
      await this.mock.connect(user).redeem(100n, user, user);

      await expect(this.mock.totalRedeemShares(epochId)).to.eventually.equal(0n);
      await expect(this.mock.totalRedeemAssets(epochId)).to.eventually.equal(0n);

      await expect(this.mock.$_fulfillRedeem(epochId, 50n))
        .to.be.revertedWithCustomError(this.mock, 'ERC7540EpochRedeemEmptyEpoch')
        .withArgs(epochId);
    });
  });
});
