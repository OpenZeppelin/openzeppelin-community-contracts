const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');

const { encodeBatch, encodeMode, CALL_TYPE_BATCH } = require('@openzeppelin/contracts/test/helpers/erc7579');
const time = require('@openzeppelin/contracts/test/helpers/time');

function shouldBehaveLikePaymaster({ postOp } = { postOp: false }) {
  describe('entryPoint', function () {
    it('should return the canonical entrypoint', async function () {
      await expect(this.paymaster.entryPoint()).to.eventually.equal(entrypoint);
    });
  });

  describe('validatePaymasterUserOp', function () {
    beforeEach(async function () {
      this.deposit = ethers.parseEther('1');
      await this.paymaster.deposit({ value: this.deposit });
      this.userOp ??= {
        paymaster: this.paymaster,
      };
    });

    it('sponsors a user operation', async function () {
      const signedUserOp = await this.account
        .createUserOp({
          ...this.userOp,
          callData: this.account.interface.encodeFunctionData('execute', [
            encodeMode({ callType: CALL_TYPE_BATCH }),
            encodeBatch({
              target: this.target,
              data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
            }),
          ]),
        })
        .then(op => this.paymasterSignUserOp(op, 0n, 0n))
        .then(op => this.signUserOp(op));

      // paymaster balance before
      await expect(entrypoint.balanceOf(this.paymaster)).to.eventually.eq(this.deposit);

      // execute sponsored user operation
      const handleOpsTx = entrypoint.handleOps([signedUserOp.packed], this.receiver);
      await expect(handleOpsTx).to.changeEtherBalance(this.account, 0n); // no balance change
      await expect(handleOpsTx).to.emit(this.target, 'MockFunctionCalledExtra').withArgs(this.account, 0n);
      if (postOp)
        expect(handleOpsTx).to.emit(this.paymaster, 'PaymasterDataPostOp').withArgs(signedUserOp.paymasterData);

      // paymaster balance after
      await expect(entrypoint.balanceOf(this.paymaster)).to.eventually.be.lessThan(this.deposit);
    });

    it('reverts if the caller is not the entrypoint', async function () {
      const operation = await this.account.createUserOp(this.userOp);

      await expect(
        this.paymaster.connect(this.other).validatePaymasterUserOp(operation.packed, ethers.ZeroHash, 100_000n),
      )
        .to.be.revertedWithCustomError(this.paymaster, 'PaymasterUnauthorized')
        .withArgs(this.other);
    });
  });

  describe('postOp', function () {
    it('reverts if the caller is not the entrypoint', async function () {
      await expect(this.paymaster.connect(this.other).postOp(0, '0x', 0, 0))
        .to.be.revertedWithCustomError(this.paymaster, 'PaymasterUnauthorized')
        .withArgs(this.other);
    });
  });

  describe('deposit lifecycle', function () {
    it('deposits and withdraws effectively', async function () {
      const value = 100n;
      await expect(this.paymaster.connect(this.other).deposit({ value })).to.changeEtherBalances(
        [this.other, entrypoint],
        [-value, value],
      );
      await expect(this.paymaster.withdraw(this.receiver, value)).to.changeEtherBalances(
        [entrypoint, this.receiver],
        [-value, value],
      );
    });

    it('reverts when an unauthorized caller tries to withdraw', async function () {
      await expect(this.paymaster.connect(this.other).withdraw(this.receiver, 100n)).to.be.reverted;
    });
  });

  describe('stake lifecycle', function () {
    it('adds and removes stake effectively', async function () {
      const value = 100n;
      const delay = time.duration.hours(10);

      // stake
      await expect(this.paymaster.connect(this.other).addStake(delay, { value })).to.changeEtherBalances(
        [this.other, entrypoint],
        [-value, value],
      );
      // unlock
      await this.paymaster.unlockStake();
      await time.increaseBy.timestamp(delay);
      // withdraw stake
      await expect(this.paymaster.withdrawStake(this.receiver)).to.changeEtherBalances(
        [entrypoint, this.receiver],
        [-value, value],
      );
    });

    it('reverts when an unauthorized caller tries to unlock stake', async function () {
      await expect(this.paymaster.connect(this.other).unlockStake()).to.be.reverted;
    });

    it('reverts when an unauthorized caller tries to withdraw stake', async function () {
      await expect(this.paymaster.connect(this.other).withdrawStake(this.receiver)).to.be.reverted;
    });
  });
}

module.exports = {
  shouldBehaveLikePaymaster,
};
