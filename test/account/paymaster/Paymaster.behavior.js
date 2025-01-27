const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const time = require('@openzeppelin/contracts/test/helpers/time');
const { encodeBatch, encodeMode, CALL_TYPE_BATCH } = require('@openzeppelin/contracts/test/helpers/erc7579');

function shouldBehaveLikePaymaster() {
  describe('entryPoint', function () {
    it('should return the canonical entrypoint', async function () {
      await expect(this.mock.entryPoint()).to.eventually.equal(entrypoint);
    });
  });

  describe('validatePaymasterUserOp', function () {
    beforeEach(async function () {
      this.deposit = ethers.parseEther('1');
      await this.mock.connect(this.depositor).deposit({ value: this.deposit });
      this.userOp ??= {
        paymaster: this.mock,
      };
    });

    it('sponsors a user operation', async function () {
      const userOp = { ...this.userOp };
      userOp.callData = this.accountMock.interface.encodeFunctionData('execute', [
        encodeMode({ callType: CALL_TYPE_BATCH }),
        encodeBatch([
          {
            target: this.target.target,
            data: this.target.interface.encodeFunctionData('mockFunction'),
          },
        ]),
      ]);
      const operation = await this.accountMock.createUserOp(this.userOp);
      const userSignedUserOp = await this.signUserOp(operation);
      const paymasterSignedUserOp = await this.paymasterSignUserOp(userSignedUserOp, 0, 0);

      await expect(entrypoint.balanceOf(this.mock)).to.eventually.eq(this.deposit);
      const handleOpsTx = await entrypoint.handleOps([paymasterSignedUserOp.packed], this.receiver);
      await expect(entrypoint.balanceOf(this.mock)).to.eventually.be.lessThan(this.deposit);
      expect(handleOpsTx).to.emit(this.target, 'MockFunctionCalledExtra');
      expect(handleOpsTx).to.not.changeEtherBalance(this.accountMock, 1n);
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
