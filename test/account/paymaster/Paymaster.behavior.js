const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const time = require('@openzeppelin/contracts/test/helpers/time');
const { encodeBatch, encodeMode, CALL_TYPE_BATCH } = require('@openzeppelin/contracts/test/helpers/erc7579');

function shouldBehaveLikePaymaster({ postOp } = { postOp: false }) {
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
      expect(handleOpsTx).to.not.changeEtherBalance(this.accountMock);

      if (postOp)
        expect(handleOpsTx).to.emit(this.mock, 'PaymasterDataPostOp').withArgs(paymasterSignedUserOp.paymasterData);
    });

    it('reverts if the caller is not the entrypoint', async function () {
      const operation = await this.accountMock.createUserOp(this.userOp);
      await expect(this.mock.connect(this.other).validatePaymasterUserOp(operation.packed, ethers.ZeroHash, 100_000n))
        .to.be.revertedWithCustomError(this.mock, 'PaymasterUnauthorized')
        .withArgs(this.other);
    });
  });

  describe('postOp', function () {
    it('reverts if the caller is not the entrypoint', async function () {
      await expect(this.mock.connect(this.other).postOp(0, '0x', 0, 0)).to.be.reverted;
    });
  });

  describe('deposit lifecycle', function () {
    it('deposits and withdraws effectively', async function () {
      const value = 100n;
      const depositTx = await this.mock.connect(this.depositor).deposit({ value });
      expect(depositTx).to.changeEtherBalance([this.depositor, entrypoint], [value * -1n, value]);
      const withdrawTx = await this.mock.withdraw(this.receiver, value);
      expect(withdrawTx).to.changeEtherBalance([entrypoint, this.receiver], [value * -1n, value]);
    });

    it('reverts when an unauthorized caller tries to withdraw', async function () {
      await expect(this.mock.connect(this.other).withdraw(this.receiver, 100n)).to.be.reverted;
    });
  });

  describe('stake lifecycle', function () {
    it('adds and removes stake effectively', async function () {
      const value = 100;
      const delay = time.duration.hours(10);
      const stakeTx = await this.mock.connect(this.staker).addStake(delay, {
        value,
      });
      expect(stakeTx).to.changeEtherBalance([this.staker, entrypoint], [value * -1, value]);
      await this.mock.unlockStake().then(() => time.increaseBy.timestamp(delay));
      const withdrawTx = await this.mock.withdrawStake(this.receiver);
      expect(withdrawTx).to.changeEtherBalance([entrypoint, this.receiver], [value * -1, value]);
    });

    it('reverts when an unauthorized caller tries to withdraw stake', async function () {
      await expect(this.mock.connect(this.other).withdrawStake(this.receiver)).to.be.reverted;
    });
  });
}

module.exports = {
  shouldBehaveLikePaymaster,
};
