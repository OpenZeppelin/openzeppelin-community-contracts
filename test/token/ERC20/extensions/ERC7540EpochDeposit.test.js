const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const time = require('@openzeppelin/contracts/test/helpers/time');
const { shouldBehaveLikeERC7540Operator, shouldBehaveLikeERC7540Deposit } = require('./ERC7540.behavior');
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

// Advances time so that `currentDepositEpoch() > epochId`. Idempotent: no-op if already past.
async function advancePast(epochId) {
  const now = await time.clock.timestamp();
  const target = (BigInt(epochId) + 1n) * week;
  if (now < target) await time.increaseTo.timestamp(target);
}

describe('ERC7540EpochDeposit', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));

    this.getRequestId = tx => time.clockFromReceipt.timestamp(tx).then(timestamp => timestamp / week);

    // Behavior-test plumbing: fulfill the whole epoch at the (assets, shares) rate.
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
      await expect(this.mock.currentDepositEpoch()).to.eventually.equal(now / week);
    });
  });

  shouldBehaveLikeERC7540Operator();
  shouldBehaveLikeERC7540Deposit({ supportCustomFulfill: false });
  shouldBehaveLikeERC7575();

  describe('epoch state and getters', function () {
    let user;

    beforeEach(async function () {
      [, user] = await ethers.getSigners();
      await this.token.$_mint(user, 1000n);
      await this.token.connect(user).approve(this.mock, ethers.MaxUint256);
    });

    it('`requestDeposit` returns the current epoch as `requestId`', async function () {
      const tx = await this.mock.connect(user).requestDeposit(100n, user, user);
      const expected = (await time.clockFromReceipt.timestamp(tx)) / week;
      // requestId is also retrievable via the event (indexed third topic)
      await expect(tx).to.emit(this.mock, 'DepositRequest').withArgs(user, user, expected, user, 100n);
    });

    it('`totalDepositAssets` / `totalDepositShares` reflect storage', async function () {
      const tx = await this.mock.connect(user).requestDeposit(100n, user, user);
      const epochId = await this.getRequestId(tx);

      await expect(this.mock.totalDepositAssets(epochId)).to.eventually.equal(100n);
      await expect(this.mock.totalDepositShares(epochId)).to.eventually.equal(0n);

      await advancePast(epochId);
      await this.mock.$_fulfillDeposit(epochId, 42n);

      await expect(this.mock.totalDepositAssets(epochId)).to.eventually.equal(100n);
      await expect(this.mock.totalDepositShares(epochId)).to.eventually.equal(42n);
    });

    it('`_convertToDepositShares` returns 0 when `totalAssets == 0`', async function () {
      // unknown epoch -> totalAssets = 0
      await expect(this.mock.$_convertToDepositShares(999n, 100n, 0n)).to.eventually.equal(0n);
    });

    it('`_convertToDepositAssets` returns 0 when `totalShares == 0`', async function () {
      // pending epoch -> totalShares = 0
      const tx = await this.mock.connect(user).requestDeposit(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await expect(this.mock.$_convertToDepositAssets(epochId, 50n, 0n)).to.eventually.equal(0n);
    });

    it('`_convertToDepositShares` applies the locked rate', async function () {
      const tx = await this.mock.connect(user).requestDeposit(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);
      await this.mock.$_fulfillDeposit(epochId, 50n); // rate 1 asset = 0.5 shares

      // Floor: floor(40 * 50 / 100) = 20
      await expect(this.mock.$_convertToDepositShares(epochId, 40n, 0n)).to.eventually.equal(20n);
      // Ceil: ceil(33 * 50 / 100) = 17
      await expect(this.mock.$_convertToDepositShares(epochId, 33n, 1n)).to.eventually.equal(17n);
    });

    it('`_convertToDepositAssets` applies the locked rate', async function () {
      const tx = await this.mock.connect(user).requestDeposit(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);
      await this.mock.$_fulfillDeposit(epochId, 50n);

      // Floor: floor(10 * 100 / 50) = 20
      await expect(this.mock.$_convertToDepositAssets(epochId, 10n, 0n)).to.eventually.equal(20n);
      // Ceil: ceil(11 * 100 / 50) = 22
      await expect(this.mock.$_convertToDepositAssets(epochId, 11n, 1n)).to.eventually.equal(22n);
    });

    it('`_pendingAvailableDepositRequest` masks drained epochs', async function () {
      const tx = await this.mock.connect(user).requestDeposit(100n, user, user);
      const epochId = await this.getRequestId(tx);

      // Pending: totalAssets > 0 -> returns requests[c]
      await expect(this.mock.$_pendingAvailableDepositRequest(epochId, user)).to.eventually.equal(100n);

      // Unknown epoch: totalAssets == 0 -> returns 0
      await expect(this.mock.$_pendingAvailableDepositRequest(999n, user)).to.eventually.equal(0n);
    });

    it('pending vs. claimable sentinel distinguishes states', async function () {
      const tx = await this.mock.connect(user).requestDeposit(100n, user, user);
      const epochId = await this.getRequestId(tx);

      // Pending state
      await expect(this.mock.pendingDepositRequest(epochId, user)).to.eventually.equal(100n);
      await expect(this.mock.claimableDepositRequest(epochId, user)).to.eventually.equal(0n);

      await advancePast(epochId);
      await this.mock.$_fulfillDeposit(epochId, 42n);

      // Claimable state
      await expect(this.mock.pendingDepositRequest(epochId, user)).to.eventually.equal(0n);
      await expect(this.mock.claimableDepositRequest(epochId, user)).to.eventually.equal(100n);

      // Consume the full claim
      await this.mock.connect(user).deposit(100n, user, ethers.Typed.address(user));

      // Fully-claimed (drained): totalAssets and totalShares both reach 0
      await expect(this.mock.totalDepositAssets(epochId)).to.eventually.equal(0n);
      await expect(this.mock.totalDepositShares(epochId)).to.eventually.equal(0n);
      await expect(this.mock.pendingDepositRequest(epochId, user)).to.eventually.equal(0n);
      await expect(this.mock.claimableDepositRequest(epochId, user)).to.eventually.equal(0n);
      await expect(this.mock.maxDeposit(user)).to.eventually.equal(0n);
      await expect(this.mock.maxMint(user)).to.eventually.equal(0n);
    });
  });

  describe('_fulfillDeposit', function () {
    let user;

    beforeEach(async function () {
      [, user] = await ethers.getSigners();
      await this.token.$_mint(user, 1000n);
      await this.token.connect(user).approve(this.mock, ethers.MaxUint256);
    });

    it('emits `ERC7540EpochDepositFulfilled` with the locked rate', async function () {
      const tx = await this.mock.connect(user).requestDeposit(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);

      await expect(this.mock.$_fulfillDeposit(epochId, 42n))
        .to.emit(this.mock, 'ERC7540EpochDepositFulfilled')
        .withArgs(epochId, 100n, 42n);
    });

    it('reverts `TooEarly` when the epoch is still the current one', async function () {
      const tx = await this.mock.connect(user).requestDeposit(100n, user, user);
      const epochId = await this.getRequestId(tx);
      // Do NOT advance time — epochId == currentDepositEpoch()

      await expect(this.mock.$_fulfillDeposit(epochId, 42n))
        .to.be.revertedWithCustomError(this.mock, 'ERC7540EpochDepositTooEarly')
        .withArgs(epochId);
    });

    it('reverts `EmptyEpoch` for an epoch with no requests', async function () {
      const current = await this.mock.currentDepositEpoch();
      await advancePast(current);

      await expect(this.mock.$_fulfillDeposit(current, 42n))
        .to.be.revertedWithCustomError(this.mock, 'ERC7540EpochDepositEmptyEpoch')
        .withArgs(current);
    });

    it('reverts `AlreadyFulfilled` on a second non-zero fulfill', async function () {
      const tx = await this.mock.connect(user).requestDeposit(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);
      await this.mock.$_fulfillDeposit(epochId, 42n);

      await expect(this.mock.$_fulfillDeposit(epochId, 50n))
        .to.be.revertedWithCustomError(this.mock, 'ERC7540EpochDepositAlreadyFulfilled')
        .withArgs(epochId);
    });

    // Documents the assumption baked into the sentinel: admin fulfilling at 0 is a no-op,
    // not a permanent confiscation. The admin can retry with the correct value.
    it('a 0-share fulfillment is a no-op and can be recovered by re-fulfilling', async function () {
      const tx = await this.mock.connect(user).requestDeposit(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);

      await this.mock.$_fulfillDeposit(epochId, 0n);

      // State is still "pending" — sentinel hasn't tripped
      await expect(this.mock.totalDepositShares(epochId)).to.eventually.equal(0n);
      await expect(this.mock.pendingDepositRequest(epochId, user)).to.eventually.equal(100n);
      await expect(this.mock.claimableDepositRequest(epochId, user)).to.eventually.equal(0n);

      // Re-fulfill with the correct value
      await expect(this.mock.$_fulfillDeposit(epochId, 42n))
        .to.emit(this.mock, 'ERC7540EpochDepositFulfilled')
        .withArgs(epochId, 100n, 42n);
      await expect(this.mock.totalDepositShares(epochId)).to.eventually.equal(42n);
      await expect(this.mock.claimableDepositRequest(epochId, user)).to.eventually.equal(100n);
    });
  });

  describe('multi-epoch flow', function () {
    it('a controller can hold requests across multiple epochs and claim each', async function () {
      const [, user] = await ethers.getSigners();
      await this.token.$_mint(user, 1000n);
      await this.token.connect(user).approve(this.mock, ethers.MaxUint256);

      // Epoch A
      const txA = await this.mock.connect(user).requestDeposit(100n, user, user);
      const epochA = await this.getRequestId(txA);

      // Advance one week -> Epoch B
      await time.increaseTo.timestamp((epochA + 1n) * week);
      const txB = await this.mock.connect(user).requestDeposit(50n, user, user);
      const epochB = await this.getRequestId(txB);
      expect(epochB).to.equal(epochA + 1n);

      // Advance and fulfill both
      await advancePast(epochB);
      await this.mock.$_fulfillDeposit(epochA, 200n); // 100 assets -> 200 shares
      await this.mock.$_fulfillDeposit(epochB, 50n); //  50 assets ->  50 shares

      await expect(this.mock.maxDeposit(user)).to.eventually.equal(150n);
      await expect(this.mock.maxMint(user)).to.eventually.equal(250n);

      // Claim a single share - hits epochA (front of queue) only
      await this.mock.connect(user).mint(50n, user, ethers.Typed.address(user));
      await expect(this.mock.balanceOf(user)).to.eventually.equal(50n);

      // Claim the rest - drains epochA then takes from epochB
      await this.mock.connect(user).mint(this.mock.maxMint(user), user, ethers.Typed.address(user));
      await expect(this.mock.balanceOf(user)).to.eventually.equal(250n);
      await expect(this.mock.maxMint(user)).to.eventually.equal(0n);
    });

    it('multiple controllers in the same epoch share pro-rata', async function () {
      const [, alice, bob, carol] = await ethers.getSigners();
      for (const user of [alice, bob, carol]) {
        await this.token.$_mint(user, 1000n);
        await this.token.connect(user).approve(this.mock, ethers.MaxUint256);
      }

      const txA = await this.mock.connect(alice).requestDeposit(30n, alice, alice);
      await this.mock.connect(bob).requestDeposit(40n, bob, bob);
      await this.mock.connect(carol).requestDeposit(30n, carol, carol);
      const epochId = await this.getRequestId(txA);

      // Total assets pending in this epoch
      await expect(this.mock.totalDepositAssets(epochId)).to.eventually.equal(100n);

      await advancePast(epochId);
      await this.mock.$_fulfillDeposit(epochId, 200n); // 100 -> 200, exact rate 1:2

      // Each controller can mint their pro-rata share
      await expect(this.mock.maxMint(alice)).to.eventually.equal(60n);
      await expect(this.mock.maxMint(bob)).to.eventually.equal(80n);
      await expect(this.mock.maxMint(carol)).to.eventually.equal(60n);

      // Claim in order — each pops their queue entry without affecting the others
      await this.mock.connect(alice).deposit(30n, alice, ethers.Typed.address(alice));
      await this.mock.connect(bob).deposit(40n, bob, ethers.Typed.address(bob));
      await this.mock.connect(carol).deposit(30n, carol, ethers.Typed.address(carol));

      await expect(this.mock.balanceOf(alice)).to.eventually.equal(60n);
      await expect(this.mock.balanceOf(bob)).to.eventually.equal(80n);
      await expect(this.mock.balanceOf(carol)).to.eventually.equal(60n);

      // Epoch fully drained
      await expect(this.mock.totalDepositAssets(epochId)).to.eventually.equal(0n);
      await expect(this.mock.totalDepositShares(epochId)).to.eventually.equal(0n);
    });
  });

  describe('depositEpochs', function () {
    let user;

    beforeEach(async function () {
      [, user] = await ethers.getSigners();
      await this.token.$_mint(user, 10000n);
      await this.token.connect(user).approve(this.mock, ethers.MaxUint256);
    });

    it('returns empty for a controller with no requests', async function () {
      await expect(this.mock.depositEpochs(user, 0, ethers.MaxUint256)).to.eventually.deep.equal([]);
      await expect(this.mock.depositEpochs(user, 0, 10)).to.eventually.deep.equal([]);
    });

    it('returns each epoch in queue order (oldest first)', async function () {
      const e0 = await this.mock.currentDepositEpoch();
      await this.mock.connect(user).requestDeposit(100n, user, user);
      await time.increaseTo.timestamp((e0 + 1n) * week);
      await this.mock.connect(user).requestDeposit(100n, user, user);
      await time.increaseTo.timestamp((e0 + 2n) * week);
      await this.mock.connect(user).requestDeposit(100n, user, user);

      await expect(this.mock.depositEpochs(user, 0, ethers.MaxUint256)).to.eventually.deep.equal([
        e0,
        e0 + 1n,
        e0 + 2n,
      ]);
    });

    it('collapses multiple requests in the same epoch into one entry', async function () {
      const e0 = await this.mock.currentDepositEpoch();
      await this.mock.connect(user).requestDeposit(50n, user, user);
      await this.mock.connect(user).requestDeposit(50n, user, user);

      await expect(this.mock.depositEpochs(user, 0, ethers.MaxUint256)).to.eventually.deep.equal([e0]);
    });

    it('pops fully-claimed epochs from the queue', async function () {
      const e0 = await this.mock.currentDepositEpoch();
      await this.mock.connect(user).requestDeposit(100n, user, user);
      await time.increaseTo.timestamp((e0 + 1n) * week);
      await this.mock.connect(user).requestDeposit(100n, user, user);

      await advancePast(e0 + 1n);
      await this.mock.$_fulfillDeposit(e0, 50n);
      await this.mock.$_fulfillDeposit(e0 + 1n, 50n);

      await expect(this.mock.depositEpochs(user, 0, ethers.MaxUint256)).to.eventually.deep.equal([e0, e0 + 1n]);

      // Claim the first epoch fully — _consumeClaimableDeposit pops it from the queue
      await this.mock.connect(user).deposit(100n, user, ethers.Typed.address(user));
      await expect(this.mock.depositEpochs(user, 0, ethers.MaxUint256)).to.eventually.deep.equal([e0 + 1n]);
    });

    it('paginates with [start, end)', async function () {
      const e0 = await this.mock.currentDepositEpoch();
      for (let i = 0; i < 4; i++) {
        await this.mock.connect(user).requestDeposit(10n, user, user);
        await time.increaseTo.timestamp((e0 + BigInt(i + 1)) * week);
      }
      const all = [e0, e0 + 1n, e0 + 2n, e0 + 3n];

      await expect(this.mock.depositEpochs(user, 0, 4)).to.eventually.deep.equal(all);
      await expect(this.mock.depositEpochs(user, 1, 3)).to.eventually.deep.equal(all.slice(1, 3));
      await expect(this.mock.depositEpochs(user, 0, 1)).to.eventually.deep.equal(all.slice(0, 1));
    });

    it('clamps out-of-bound `start` and `end`', async function () {
      const e0 = await this.mock.currentDepositEpoch();
      await this.mock.connect(user).requestDeposit(100n, user, user);

      // end > length → clamped
      await expect(this.mock.depositEpochs(user, 0, ethers.MaxUint256)).to.eventually.deep.equal([e0]);
      // start > length → empty after both clamps
      await expect(this.mock.depositEpochs(user, 10, ethers.MaxUint256)).to.eventually.deep.equal([]);
      // start > end → empty
      await expect(this.mock.depositEpochs(user, 1, 0)).to.eventually.deep.equal([]);
    });
  });

  describe('queue limit', function () {
    it('enforces `_requestQueueLimit` per controller', async function () {
      const [, user] = await ethers.getSigners();
      await this.token.$_mint(user, 10000n);
      await this.token.connect(user).approve(this.mock, ethers.MaxUint256);

      // Fill the queue with 32 distinct epochs (default limit)
      let epoch = await this.mock.currentDepositEpoch();
      for (let i = 0; i < 32; i++) {
        await this.mock.connect(user).requestDeposit(1n, user, user);
        epoch = epoch + 1n;
        await time.increaseTo.timestamp(epoch * week);
      }

      // The 33rd distinct epoch should revert (bare require — no custom error)
      await expect(this.mock.connect(user).requestDeposit(1n, user, user)).to.be.reverted;
    });

    it('multiple requests in the same epoch share one queue slot', async function () {
      const [, user] = await ethers.getSigners();
      await this.token.$_mint(user, 1000n);
      await this.token.connect(user).approve(this.mock, ethers.MaxUint256);

      // Many requests in the same epoch - all share the same queue entry
      for (let i = 0; i < 50; i++) {
        await this.mock.connect(user).requestDeposit(1n, user, user);
      }
      // Did not hit the queue limit despite > 32 requests
      const epochId = await this.mock.currentDepositEpoch();
      await expect(this.mock.totalDepositAssets(epochId)).to.eventually.equal(50n);
    });
  });

  describe('edge cases', function () {
    it('a 1-share fulfillment makes mint(0) a no-op (per-claim rounding edge)', async function () {
      const [, user] = await ethers.getSigners();
      await this.token.$_mint(user, 1000n);
      await this.token.connect(user).approve(this.mock, ethers.MaxUint256);

      const tx = await this.mock.connect(user).requestDeposit(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);
      await this.mock.$_fulfillDeposit(epochId, 1n); // 100 assets -> 1 share

      // mint(0) is a valid no-op call
      const before = await this.mock.balanceOf(user);
      await this.mock.connect(user).mint(0n, user, ethers.Typed.address(user));
      await expect(this.mock.balanceOf(user)).to.eventually.equal(before);

      // Asset-driven `deposit` is the path that can absorb the floor-rounding dust
      await this.mock.connect(user).deposit(100n, user, ethers.Typed.address(user));
      await expect(this.mock.balanceOf(user)).to.eventually.equal(1n);
    });

    it('saturating sub absorbs ceil/floor excess; drained-state dust is hidden from views', async function () {
      // Pathological tiny-totals scenario to trigger Case A overshoot in the share-driven
      // path. Uses the internal `$_consumeClaimableMint` to bypass the public `maxMint`
      // guard so we can force the rounding excess that saturating sub is designed to absorb.
      //
      // Setup: r_alice=2, r_bob=3, totalAssets=5. Fulfill S=3.
      //   Alice Case A: requested=ceil(2*3/5)=2, batchAssets uncapped=floor(2*5/3)=3 (overshoot by 1)
      //   Sat-sub: r_alice 2->0, totalAssets 5->2, totalShares 3->1.
      //   Bob Case B: requested=ceil(3*1/2)=2 > shares=1, batchAssets=floor(1*2/1)=2.
      //   Sat-sub: r_bob saturates 3->1 (dust), totalAssets 2->0, totalShares 1->0 (drained).
      const [, alice, bob] = await ethers.getSigners();
      for (const u of [alice, bob]) {
        await this.token.$_mint(u, 1000n);
        await this.token.connect(u).approve(this.mock, ethers.MaxUint256);
      }

      const tx = await this.mock.connect(alice).requestDeposit(2n, alice, alice);
      await this.mock.connect(bob).requestDeposit(3n, bob, bob);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);
      await this.mock.$_fulfillDeposit(epochId, 3n);

      // Alice's full claim absorbs the overshoot
      await this.mock.$_consumeClaimableMint(2n, alice);
      await expect(this.mock.totalDepositAssets(epochId)).to.eventually.equal(2n);
      await expect(this.mock.totalDepositShares(epochId)).to.eventually.equal(1n);

      // Bob's partial claim drains the pool and leaves dust in `requests[bob]`
      await this.mock.$_consumeClaimableMint(1n, bob);
      await expect(this.mock.totalDepositAssets(epochId)).to.eventually.equal(0n);
      await expect(this.mock.totalDepositShares(epochId)).to.eventually.equal(0n);

      // The 1-wei dust in bob's slot is invisible through every public view
      await expect(this.mock.pendingDepositRequest(epochId, bob)).to.eventually.equal(0n);
      await expect(this.mock.claimableDepositRequest(epochId, bob)).to.eventually.equal(0n);
      await expect(this.mock.maxDeposit(bob)).to.eventually.equal(0n);
      await expect(this.mock.maxMint(bob)).to.eventually.equal(0n);
    });

    it('a fully-drained epoch keeps the {_fulfillDeposit} sentinel intact', async function () {
      // After a normal full distribution, `totalAssets` and `totalShares` both reach 0.
      // The sentinel relies on `totalAssets > 0` to detect "still has pending value", so
      // a re-fulfill attempt must revert with `EmptyEpoch` rather than silently re-trigger.
      const [, user] = await ethers.getSigners();
      await this.token.$_mint(user, 1000n);
      await this.token.connect(user).approve(this.mock, ethers.MaxUint256);

      const tx = await this.mock.connect(user).requestDeposit(100n, user, user);
      const epochId = await this.getRequestId(tx);
      await advancePast(epochId);
      await this.mock.$_fulfillDeposit(epochId, 42n);
      await this.mock.connect(user).deposit(100n, user, ethers.Typed.address(user));

      await expect(this.mock.totalDepositAssets(epochId)).to.eventually.equal(0n);
      await expect(this.mock.totalDepositShares(epochId)).to.eventually.equal(0n);

      await expect(this.mock.$_fulfillDeposit(epochId, 50n))
        .to.be.revertedWithCustomError(this.mock, 'ERC7540EpochDepositEmptyEpoch')
        .withArgs(epochId);
    });
  });
});
