const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const time = require('@openzeppelin/contracts/test/helpers/time');
const { shouldSupportInterfaces, INTERFACE_IDS } = require('../../../utils/introspection/SupportsInterface.behavior');

const name = 'Vault Shares';
const symbol = 'vSHR';
const tokenName = 'Asset Token';
const tokenSymbol = 'AST';
const initialBalance = ethers.parseEther('1000');
const amount = ethers.parseEther('100');
const delay = 3600n;

async function fixture() {
  const [owner, controller, receiver, operator, other] = await ethers.getSigners();

  const token = await ethers.deployContract('$ERC20', [tokenName, tokenSymbol]);
  const mock = await ethers.deployContract('$ERC7540DelayMock', [name, symbol, token]);

  await token.$_mint(owner, initialBalance);
  await token.connect(owner).approve(mock, ethers.MaxUint256);
  await mock.connect(owner).setOperator(operator, true);
  await mock.connect(controller).setOperator(operator, true);

  return { owner, controller, receiver, operator, other, token, mock };
}

describe('ERC7540Delay', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('metadata', function () {
    it('token', async function () {
      await expect(this.mock.asset()).to.eventually.equal(this.token.target);
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

    it('reports default delay', async function () {
      await expect(this.mock.depositDelay(this.owner)).to.eventually.equal(delay);
      await expect(this.mock.redeemDelay(this.owner)).to.eventually.equal(delay);
    });

    describe('supports ERC-7540 interfaces', function () {
      expect(INTERFACE_IDS.ERC7540Operator).to.equal('0xe3bc4e65');
      expect(INTERFACE_IDS.ERC7540Deposit).to.equal('0xce3bbe50');
      expect(INTERFACE_IDS.ERC7540Redeem).to.equal('0x620ee8e4');

      shouldSupportInterfaces(['ERC7540Operator', 'ERC7540Deposit', 'ERC7540Redeem']);
    });
  });

  describe('deposit flow', function () {
    describe('requestDeposit', function () {
      it('transfers tokens and emits DepositRequest with timepoint-based requestId', async function () {
        const assetsBefore = await this.mock.totalAssets();

        const tx = this.mock.connect(this.owner).requestDeposit(amount, this.controller, this.owner);
        const requestId = (await time.clockFromReceipt.timestamp(tx)) + delay;

        await expect(tx)
          .to.emit(this.mock, 'DepositRequest')
          .withArgs(this.controller, this.owner, requestId, this.owner, amount);

        await expect(tx).to.changeTokenBalances(this.token, [this.owner, this.mock], [-amount, amount]);

        await expect(this.mock.totalAssets()).to.eventually.equal(assetsBefore);

        await expect(this.mock.pendingDepositRequest(requestId, this.controller)).to.eventually.equal(amount);
        await expect(this.mock.claimableDepositRequest(requestId, this.controller)).to.eventually.equal(0n);

        await time.increaseTo.timestamp(requestId);

        await expect(this.mock.pendingDepositRequest(requestId, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.claimableDepositRequest(requestId, this.controller)).to.eventually.equal(amount);
      });

      it('operator can trigger request deposit on behalf of owner', async function () {
        const tx = this.mock.connect(this.operator).requestDeposit(amount, this.controller, this.owner);
        const requestId = (await time.clockFromReceipt.timestamp(tx)) + delay;

        await expect(tx)
          .to.emit(this.mock, 'DepositRequest')
          .withArgs(this.controller, this.owner, requestId, this.operator, amount);

        await expect(tx).to.changeTokenBalances(this.token, [this.owner, this.mock], [-amount, amount]);
      });

      it('reverts when caller is neither owner nor operator of owner', async function () {
        await expect(this.mock.connect(this.other).requestDeposit(amount, this.controller, this.owner))
          .to.be.revertedWithCustomError(this.mock, 'ERC7540InvalidOperator')
          .withArgs(this.owner, this.other);
      });

      it('totalAssets excludes in-flight deposits', async function () {
        await this.mock.connect(this.owner).requestDeposit(amount, this.controller, this.owner);
        await expect(this.mock.totalAssets()).to.eventually.equal(0n);
      });
    });

    describe('claim', function () {
      beforeEach(async function () {
        const tx = this.mock.connect(this.operator).requestDeposit(amount, this.controller, this.owner);
        this.requestId = (await time.clockFromReceipt.timestamp(tx)) + delay;
        await time.increaseTo.timestamp(this.requestId);
      });

      describe('via deposit()', function () {
        it('mints shares 1:1 to receiver and emits Deposit', async function () {
          await expect(this.mock.pendingDepositRequest(this.requestId, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableDepositRequest(this.requestId, this.controller)).to.eventually.equal(amount);
          await expect(this.mock.maxDeposit(this.controller)).to.eventually.equal(amount);

          const assetsBefore = await this.mock.totalAssets();
          const supplyBefore = await this.mock.totalSupply();

          const tx = this.mock
            .connect(this.controller)
            .deposit(amount, this.receiver, ethers.Typed.address(this.controller));

          await expect(tx).to.emit(this.mock, 'Deposit').withArgs(this.controller, this.receiver, amount, amount);

          await expect(tx).to.changeTokenBalance(this.mock, this.receiver, amount);

          await expect(this.mock.pendingDepositRequest(this.requestId, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableDepositRequest(this.requestId, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.maxDeposit(this.controller)).to.eventually.equal(0n);
          await expect(this.mock.totalAssets()).to.eventually.equal(assetsBefore + amount);
          await expect(this.mock.totalSupply()).to.eventually.equal(supplyBefore + amount);
        });

        it('operator can trigger deposit on behalf of controller', async function () {
          const tx = this.mock
            .connect(this.operator)
            .deposit(amount, this.receiver, ethers.Typed.address(this.controller));

          await expect(tx).to.emit(this.mock, 'Deposit').withArgs(this.operator, this.receiver, amount, amount);

          await expect(tx).to.changeTokenBalance(this.mock, this.receiver, amount);
        });

        it('reverts when caller is neither owner nor operator of owner', async function () {
          await expect(
            this.mock.connect(this.other).deposit(amount, this.receiver, ethers.Typed.address(this.controller)),
          )
            .to.be.revertedWithCustomError(this.mock, 'ERC7540InvalidOperator')
            .withArgs(this.controller, this.other);
        });
      });

      describe('via mint()', function () {
        it('mints exactly the requested shares and emits Deposit', async function () {
          await expect(this.mock.pendingDepositRequest(this.requestId, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableDepositRequest(this.requestId, this.controller)).to.eventually.equal(amount);
          await expect(this.mock.maxMint(this.controller)).to.eventually.equal(amount);

          const assetsBefore = await this.mock.totalAssets();
          const supplyBefore = await this.mock.totalSupply();

          const tx = this.mock
            .connect(this.controller)
            .mint(amount, this.receiver, ethers.Typed.address(this.controller));

          await expect(tx).to.emit(this.mock, 'Deposit').withArgs(this.controller, this.receiver, amount, amount);

          await expect(tx).to.changeTokenBalance(this.mock, this.receiver, amount);

          await expect(this.mock.pendingDepositRequest(this.requestId, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableDepositRequest(this.requestId, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.maxMint(this.controller)).to.eventually.equal(0n);
          await expect(this.mock.totalAssets()).to.eventually.equal(assetsBefore + amount);
          await expect(this.mock.totalSupply()).to.eventually.equal(supplyBefore + amount);
        });

        it('operator can trigger mint on behalf of controller', async function () {
          const tx = this.mock
            .connect(this.operator)
            .mint(amount, this.receiver, ethers.Typed.address(this.controller));

          await expect(tx).to.emit(this.mock, 'Deposit').withArgs(this.operator, this.receiver, amount, amount);

          await expect(tx).to.changeTokenBalance(this.mock, this.receiver, amount);
        });

        it('reverts when caller is neither owner nor operator of owner', async function () {
          await expect(this.mock.connect(this.other).mint(amount, this.receiver, ethers.Typed.address(this.controller)))
            .to.be.revertedWithCustomError(this.mock, 'ERC7540InvalidOperator')
            .withArgs(this.controller, this.other);
        });
      });
    });
  });

  describe('redeem flow', function () {
    beforeEach(async function () {
      await this.token.$_mint(this.mock, initialBalance);
      await this.mock.$_mint(this.owner, initialBalance);
    });

    describe('requestRedeem', function () {
      it('burns shares, emits RedeemRequest, keeps totalSupply stable via pending counter', async function () {
        const supplyBefore = await this.mock.totalSupply();

        const tx = this.mock.connect(this.owner).requestRedeem(amount, this.controller, this.owner);
        const requestId = (await time.clockFromReceipt.timestamp(tx)) + delay;

        await expect(tx)
          .to.emit(this.mock, 'RedeemRequest')
          .withArgs(this.controller, this.owner, requestId, this.owner, amount);

        await expect(tx).to.changeTokenBalance(this.mock, this.owner, -amount);

        await expect(this.mock.totalSupply()).to.eventually.equal(supplyBefore);

        await expect(this.mock.pendingRedeemRequest(requestId, this.controller)).to.eventually.equal(amount);
        await expect(this.mock.claimableRedeemRequest(requestId, this.controller)).to.eventually.equal(0n);

        await time.increaseTo.timestamp(requestId);

        await expect(this.mock.pendingRedeemRequest(requestId, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.claimableRedeemRequest(requestId, this.controller)).to.eventually.equal(amount);
      });

      it('operator can trigger request deposit on behalf of owner', async function () {
        const tx = this.mock.connect(this.operator).requestRedeem(amount, this.controller, this.owner);
        const requestId = (await time.clockFromReceipt.timestamp(tx)) + delay;

        await expect(tx)
          .to.emit(this.mock, 'RedeemRequest')
          .withArgs(this.controller, this.owner, requestId, this.operator, amount);

        await expect(tx).to.changeTokenBalance(this.mock, this.owner, -amount);
      });

      it('spends allowance when caller is neither owner nor operator', async function () {
        await this.mock.connect(this.owner).approve(this.other, amount);

        const tx = this.mock.connect(this.other).requestRedeem(amount, this.controller, this.owner);
        const requestId = (await time.clockFromReceipt.timestamp(tx)) + delay;

        await expect(tx)
          .to.emit(this.mock, 'RedeemRequest')
          .withArgs(this.controller, this.owner, requestId, this.other, amount);

        await expect(this.mock.allowance(this.owner, this.other)).to.eventually.equal(0n);
      });

      it('revert of caller is neither owner nor operator and has no allowance', async function () {
        const tx = this.mock.connect(this.other).requestRedeem(amount, this.controller, this.owner);

        await expect(tx)
          .to.be.revertedWithCustomError(this.mock, 'ERC20InsufficientAllowance')
          .withArgs(this.other, 0n, amount);
      });
    });

    describe('claim', function () {
      beforeEach(async function () {
        const tx = this.mock.connect(this.operator).requestRedeem(amount, this.controller, this.owner);
        this.requestId = (await time.clockFromReceipt.timestamp(tx)) + delay;
        await time.increaseTo.timestamp(this.requestId);
      });

      describe('via redeem()', function () {
        it('transfers tokens to receiver and emits Withdraw', async function () {
          await expect(this.mock.pendingRedeemRequest(this.requestId, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableRedeemRequest(this.requestId, this.controller)).to.eventually.equal(amount);
          await expect(this.mock.maxRedeem(this.controller)).to.eventually.equal(amount);

          const assetsBefore = await this.mock.totalAssets();
          const supplyBefore = await this.mock.totalSupply();

          const tx = this.mock.connect(this.controller).redeem(amount, this.receiver, this.controller);

          await expect(tx)
            .to.emit(this.mock, 'Withdraw')
            .withArgs(this.controller, this.receiver, this.controller, amount, amount);

          await expect(tx).to.changeTokenBalances(this.token, [this.mock, this.receiver], [-amount, amount]);

          await expect(this.mock.pendingRedeemRequest(this.requestId, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableRedeemRequest(this.requestId, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.maxRedeem(this.controller)).to.eventually.equal(0n);
          await expect(this.mock.totalAssets()).to.eventually.equal(assetsBefore - amount);
          await expect(this.mock.totalSupply()).to.eventually.equal(supplyBefore - amount);
        });

        it('operator can trigger redeem on behalf of controller', async function () {
          const tx = this.mock.connect(this.operator).redeem(amount, this.receiver, this.controller);

          await expect(tx)
            .to.emit(this.mock, 'Withdraw')
            .withArgs(this.operator, this.receiver, this.controller, amount, amount);

          await expect(tx).to.changeTokenBalances(this.token, [this.mock, this.receiver], [-amount, amount]);
        });

        it('reverts when caller is neither owner nor operator of owner', async function () {
          await expect(this.mock.connect(this.other).redeem(amount, this.receiver, this.controller))
            .to.be.revertedWithCustomError(this.mock, 'ERC7540InvalidOperator')
            .withArgs(this.controller, this.other);
        });
      });

      describe('via withdraw()', function () {
        it('transfers exactly the requested tokens and emits Withdraw', async function () {
          await expect(this.mock.pendingRedeemRequest(this.requestId, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableRedeemRequest(this.requestId, this.controller)).to.eventually.equal(amount);
          await expect(this.mock.maxWithdraw(this.controller)).to.eventually.equal(amount);

          const assetsBefore = await this.mock.totalAssets();
          const supplyBefore = await this.mock.totalSupply();

          const tx = this.mock.connect(this.controller).withdraw(amount, this.receiver, this.controller);

          await expect(tx)
            .to.emit(this.mock, 'Withdraw')
            .withArgs(this.controller, this.receiver, this.controller, amount, amount);

          await expect(tx).to.changeTokenBalances(this.token, [this.mock, this.receiver], [-amount, amount]);

          await expect(this.mock.pendingRedeemRequest(this.requestId, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableRedeemRequest(this.requestId, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.maxWithdraw(this.controller)).to.eventually.equal(0n);
          await expect(this.mock.totalAssets()).to.eventually.equal(assetsBefore - amount);
          await expect(this.mock.totalSupply()).to.eventually.equal(supplyBefore - amount);
        });

        it('operator can trigger withdraw on behalf of controller', async function () {
          const tx = this.mock.connect(this.operator).withdraw(amount, this.receiver, this.controller);

          await expect(tx)
            .to.emit(this.mock, 'Withdraw')
            .withArgs(this.operator, this.receiver, this.controller, amount, amount);

          await expect(tx).to.changeTokenBalances(this.token, [this.mock, this.receiver], [-amount, amount]);
        });

        it('reverts when caller is neither owner nor operator of owner', async function () {
          await expect(this.mock.connect(this.other).withdraw(amount, this.receiver, this.controller))
            .to.be.revertedWithCustomError(this.mock, 'ERC7540InvalidOperator')
            .withArgs(this.controller, this.other);
        });
      });
    });
  });

  describe('operators', function () {
    for (const status of [true, false]) {
      it(`setOperator to ${status} emits event and updates status`, async function () {
        await expect(this.mock.connect(this.owner).setOperator(this.operator, status))
          .to.emit(this.mock, 'OperatorSet')
          .withArgs(this.owner, this.operator, status);

        await expect(this.mock.isOperator(this.owner, this.operator)).to.eventually.equal(status);
      });
    }
  });
});
