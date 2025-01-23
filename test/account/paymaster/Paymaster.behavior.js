const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const time = require('@openzeppelin/contracts/test/helpers/time');

function shouldBehaveLikePaymaster() {
  describe('entryPoint', function () {
    it('should return the canonical entrypoint', async function () {
      await expect(this.mock.entryPoint()).to.eventually.equal(entrypoint);
    });
  });

  describe('deposit lifecycle', function () {
    it('deposits and withdraws effectively', async function () {
      const value = 100n;
      const depositTx = await this.mock.connect(this.depositor).deposit({ value });
      expect(depositTx).to.changeEtherBalance(this.depositor, value * -1n);
      expect(depositTx).to.changeEtherBalance(entrypoint, value);
      const withdrawTx = await this.mock.$_withdraw(this.receiver, value);
      expect(withdrawTx).to.changeEtherBalance(entrypoint, value * -1n);
      expect(withdrawTx).to.changeEtherBalance(this.receiver, value);
    });
  });

  describe('stake lifecycle', function () {
    it('adds and removes stake effectively', async function () {
      const value = 100;
      const delay = time.duration.hours(10);
      const stakeTx = await this.mock.connect(this.staker).addStake(ethers.Typed.uint32(delay), {
        value,
      });
      expect(stakeTx).to.changeEtherBalance(this.staker, value * -1);
      expect(stakeTx).to.changeEtherBalance(entrypoint, value);
      await this.mock.$_unlockStake().then(() => time.increaseBy.timestamp(delay));
      const withdrawTx = await this.mock.$_withdrawStake(this.receiver);
      expect(withdrawTx).to.changeEtherBalance(entrypoint, value * -1);
      expect(withdrawTx).to.changeEtherBalance(this.receiver, value);
    });
  });
}

module.exports = {
  shouldBehaveLikePaymaster,
};
