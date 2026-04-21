const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const { shouldSupportInterfaces, INTERFACE_IDS } = require('../../../utils/introspection/SupportsInterface.behavior');

const name = 'Vault Shares';
const symbol = 'vSHR';
const tokenName = 'Asset Token';
const tokenSymbol = 'AST';
// initial vault distribution
const initialAssets = ethers.parseEther('17000000');
const initialShares = ethers.parseEther('42000000');
// other
const balance = ethers.parseEther('1000');

async function fixture() {
  const [owner, controller, receiver, operator, other] = await ethers.getSigners();

  const token = await ethers.deployContract('$ERC20', [tokenName, tokenSymbol]);
  const mock = await ethers.deployContract('$ERC7540AdminMock', [name, symbol, token]);

  await token.$_mint(mock, initialAssets);
  await mock.$_mint(owner, initialShares);

  await token.$_mint(owner, balance);
  await token.connect(owner).approve(mock, ethers.MaxUint256);
  await mock.connect(owner).setOperator(operator, true);
  await mock.connect(controller).setOperator(operator, true);

  return { owner, controller, receiver, operator, other, token, mock };
}

describe('ERC7540Admin', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
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

    describe('supports ERC-7540 interfaces', function () {
      expect(INTERFACE_IDS.ERC7540Operator).to.equal('0xe3bc4e65');
      expect(INTERFACE_IDS.ERC7540Deposit).to.equal('0xce3bbe50');
      expect(INTERFACE_IDS.ERC7540Redeem).to.equal('0x620ee8e4');

      shouldSupportInterfaces(['ERC7540Operator', 'ERC7540Deposit', 'ERC7540Redeem']);
    });
  });

  describe('deposit flow', function () {
    const assets = ethers.parseEther('100');
    const shares = (assets * initialShares) / initialAssets;

    describe('requestDeposit', function () {
      it('transfers tokens, marks as pending, emits DepositRequest with requestId 0', async function () {
        const assetsBefore = await this.mock.totalAssets();
        const supplyBefore = await this.mock.totalSupply();

        const tx = this.mock.connect(this.owner).requestDeposit(assets, this.controller, this.owner);

        await expect(tx)
          .to.emit(this.mock, 'DepositRequest')
          .withArgs(this.controller, this.owner, 0n, this.owner, assets);
        await expect(tx).to.changeTokenBalances(this.token, [this.owner, this.mock], [-assets, assets]);
        await expect(tx).to.changeTokenBalances(this.mock, [this.controller], [0n]);

        await expect(this.mock.totalAssets()).to.eventually.equal(assetsBefore);
        await expect(this.mock.totalSupply()).to.eventually.equal(supplyBefore);

        await expect(this.mock.pendingDepositRequest(0n, this.controller)).to.eventually.equal(assets);
        await expect(this.mock.claimableDepositRequest(0n, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxDeposit(this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxMint(this.controller)).to.eventually.equal(0n);
      });

      it('operator can trigger request deposit on behalf of owner', async function () {
        const tx = this.mock.connect(this.operator).requestDeposit(assets, this.controller, this.owner);

        await expect(tx)
          .to.emit(this.mock, 'DepositRequest')
          .withArgs(this.controller, this.owner, 0n, this.operator, assets);
        await expect(tx).to.changeTokenBalances(this.token, [this.owner, this.mock], [-assets, assets]);
        await expect(tx).to.changeTokenBalances(this.mock, [this.controller], [0n]);
      });

      it('reverts when caller is neither owner nor operator of owner', async function () {
        await expect(this.mock.connect(this.other).requestDeposit(assets, this.controller, this.owner))
          .to.be.revertedWithCustomError(this.mock, 'ERC7540InvalidOperator')
          .withArgs(this.owner, this.other);
      });

      it('accumulates pending across multiple requests', async function () {
        await this.mock.connect(this.owner).requestDeposit(17n, this.controller, this.owner);
        await this.mock.connect(this.owner).requestDeposit(42n, this.controller, this.owner);

        await expect(this.mock.pendingDepositRequest(0n, this.controller)).to.eventually.equal(17n + 42n);
      });
    });

    describe('fulfillDeposit', function () {
      beforeEach(async function () {
        await this.mock.connect(this.owner).requestDeposit(assets, this.controller, this.owner);
      });

      it('transitions pending to claimable and emits DepositClaimable', async function () {
        const assetsBefore = await this.mock.totalAssets();
        const supplyBefore = await this.mock.totalSupply();

        await expect(this.mock.pendingDepositRequest(0n, this.controller)).to.eventually.equal(assets);
        await expect(this.mock.claimableDepositRequest(0n, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxDeposit(this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxMint(this.controller)).to.eventually.equal(0n);

        await expect(this.mock.$_fulfillDeposit(assets, shares, this.controller))
          .to.emit(this.mock, 'DepositClaimable')
          .withArgs(this.controller, 0n, assets, shares);

        await expect(this.mock.totalAssets()).to.eventually.equal(assetsBefore);
        await expect(this.mock.totalSupply()).to.eventually.equal(supplyBefore);

        await expect(this.mock.pendingDepositRequest(0n, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.claimableDepositRequest(0n, this.controller)).to.eventually.equal(assets);
        await expect(this.mock.maxDeposit(this.controller)).to.eventually.equal(assets);
        await expect(this.mock.maxMint(this.controller)).to.eventually.equal(shares);
      });

      it('supports admin-determined share ratio', async function () {
        await expect(this.mock.pendingDepositRequest(0n, this.controller)).to.eventually.equal(assets);
        await expect(this.mock.claimableDepositRequest(0n, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxDeposit(this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxMint(this.controller)).to.eventually.equal(0n);

        await expect(this.mock.$_fulfillDeposit(assets, 42n, this.controller))
          .to.emit(this.mock, 'DepositClaimable')
          .withArgs(this.controller, 0n, assets, 42n);

        await expect(this.mock.pendingDepositRequest(0n, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.claimableDepositRequest(0n, this.controller)).to.eventually.equal(assets);
        await expect(this.mock.maxDeposit(this.controller)).to.eventually.equal(assets);
        await expect(this.mock.maxMint(this.controller)).to.eventually.equal(42n);
      });

      it('can be partially fulfilled', async function () {
        await expect(this.mock.pendingDepositRequest(0n, this.controller)).to.eventually.equal(assets);
        await expect(this.mock.claimableDepositRequest(0n, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxDeposit(this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxMint(this.controller)).to.eventually.equal(0n);

        await this.mock.$_fulfillDeposit(17n, 42n, this.controller);

        await expect(this.mock.pendingDepositRequest(0n, this.controller)).to.eventually.equal(assets - 17n);
        await expect(this.mock.claimableDepositRequest(0n, this.controller)).to.eventually.equal(17n);
        await expect(this.mock.maxDeposit(this.controller)).to.eventually.equal(17n);
        await expect(this.mock.maxMint(this.controller)).to.eventually.equal(42n);
      });

      it('reverts when fulfilling more than pending', async function () {
        await expect(this.mock.$_fulfillDeposit(assets + 1n, shares, this.controller))
          .to.be.revertedWithCustomError(this.mock, 'ERC7540DepositInsufficientPendingAssets')
          .withArgs(assets + 1n, assets);
      });
    });

    describe('claim', function () {
      beforeEach(async function () {
        await this.mock.connect(this.owner).requestDeposit(assets, this.controller, this.owner);
        await this.mock.$_fulfillDeposit(assets, shares, this.controller);
      });

      describe('via deposit()', function () {
        it('mints shares to receiver and emits Deposit', async function () {
          await expect(this.mock.pendingDepositRequest(0n, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableDepositRequest(0n, this.controller)).to.eventually.equal(assets);
          await expect(this.mock.maxDeposit(this.controller)).to.eventually.equal(assets);

          const assetsBefore = await this.mock.totalAssets();
          const supplyBefore = await this.mock.totalSupply();

          const tx = this.mock
            .connect(this.controller)
            .deposit(assets, this.receiver, ethers.Typed.address(this.controller));

          await expect(tx).to.emit(this.mock, 'Deposit').withArgs(this.controller, this.receiver, assets, shares);
          await expect(tx).to.changeTokenBalance(this.mock, this.receiver, shares);

          await expect(this.mock.pendingDepositRequest(0n, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableDepositRequest(0n, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.maxDeposit(this.controller)).to.eventually.equal(0n);
          await expect(this.mock.totalAssets()).to.eventually.equal(assetsBefore + assets);
          await expect(this.mock.totalSupply()).to.eventually.equal(supplyBefore + shares);
        });

        it('operator can trigger deposit on behalf of controller', async function () {
          const tx = this.mock
            .connect(this.operator)
            .deposit(assets, this.receiver, ethers.Typed.address(this.controller));

          await expect(tx).to.emit(this.mock, 'Deposit').withArgs(this.operator, this.receiver, assets, shares);
          await expect(tx).to.changeTokenBalance(this.mock, this.receiver, shares);
        });

        it('reverts when caller is neither owner nor operator of owner', async function () {
          await expect(
            this.mock.connect(this.other).deposit(assets, this.receiver, ethers.Typed.address(this.controller)),
          )
            .to.be.revertedWithCustomError(this.mock, 'ERC7540InvalidOperator')
            .withArgs(this.controller, this.other);
        });
      });

      describe('via mint()', function () {
        it('mints exactly the requested shares and emits Deposit', async function () {
          await expect(this.mock.pendingDepositRequest(0n, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableDepositRequest(0n, this.controller)).to.eventually.equal(assets);
          await expect(this.mock.maxMint(this.controller)).to.eventually.equal(shares);

          const assetsBefore = await this.mock.totalAssets();
          const supplyBefore = await this.mock.totalSupply();

          const tx = this.mock
            .connect(this.controller)
            .mint(shares, this.receiver, ethers.Typed.address(this.controller));

          await expect(tx).to.emit(this.mock, 'Deposit').withArgs(this.controller, this.receiver, assets, shares);

          await expect(tx).to.changeTokenBalance(this.mock, this.receiver, shares);

          await expect(this.mock.pendingDepositRequest(0n, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableDepositRequest(0n, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.maxMint(this.controller)).to.eventually.equal(0n);
          await expect(this.mock.totalAssets()).to.eventually.equal(assetsBefore + assets);
          await expect(this.mock.totalSupply()).to.eventually.equal(supplyBefore + shares);
        });

        it('operator can trigger mint on behalf of controller', async function () {
          const tx = this.mock
            .connect(this.operator)
            .mint(shares, this.receiver, ethers.Typed.address(this.controller));

          await expect(tx).to.emit(this.mock, 'Deposit').withArgs(this.operator, this.receiver, assets, shares);
          await expect(tx).to.changeTokenBalance(this.mock, this.receiver, shares);
        });

        it('reverts when caller is neither owner nor operator of owner', async function () {
          await expect(this.mock.connect(this.other).mint(shares, this.receiver, ethers.Typed.address(this.controller)))
            .to.be.revertedWithCustomError(this.mock, 'ERC7540InvalidOperator')
            .withArgs(this.controller, this.other);
        });
      });
    });
  });

  describe('redeem flow', function () {
    const shares = ethers.parseEther('100');
    const assets = (shares * initialAssets) / initialShares;

    describe('requestRedeem', function () {
      it('burns shares, marks as pending, emits RedeemRequest with requestId 0', async function () {
        const assetsBefore = await this.mock.totalAssets();
        const supplyBefore = await this.mock.totalSupply();

        // perform request redeem, and extract requestId from timing
        const tx = this.mock.connect(this.owner).requestRedeem(shares, this.controller, this.owner);

        // check event is emitted and shares are burned
        await expect(tx)
          .to.emit(this.mock, 'RedeemRequest')
          .withArgs(this.controller, this.owner, 0n, this.owner, shares);
        await expect(tx).to.changeTokenBalances(this.token, [this.controller, this.mock], [0n, 0n]);
        await expect(tx).to.changeTokenBalances(this.mock, [this.owner], [-shares]);

        // totalSupply includes shares for in-flight redeem
        await expect(this.mock.totalAssets()).to.eventually.equal(assetsBefore);
        await expect(this.mock.totalSupply()).to.eventually.equal(supplyBefore);

        // check pending redeem is registered
        await expect(this.mock.pendingRedeemRequest(0n, this.controller)).to.eventually.equal(shares);
        await expect(this.mock.claimableRedeemRequest(0n, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxRedeem(this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxWithdraw(this.controller)).to.eventually.equal(0n);
      });

      it('operator can trigger request redeem on behalf of owner', async function () {
        const tx = this.mock.connect(this.operator).requestRedeem(shares, this.controller, this.owner);

        await expect(tx)
          .to.emit(this.mock, 'RedeemRequest')
          .withArgs(this.controller, this.owner, 0n, this.operator, shares);
        await expect(tx).to.changeTokenBalances(this.token, [this.controller, this.mock], [0n, 0n]);
        await expect(tx).to.changeTokenBalances(this.mock, [this.owner], [-shares]);
      });

      it('spends allowance when caller is neither owner nor operator', async function () {
        await this.mock.connect(this.owner).approve(this.other, shares);

        const tx = this.mock.connect(this.other).requestRedeem(shares, this.controller, this.owner);

        await expect(tx)
          .to.emit(this.mock, 'RedeemRequest')
          .withArgs(this.controller, this.owner, 0n, this.other, shares);

        await expect(this.mock.allowance(this.owner, this.other)).to.eventually.equal(0n);
      });

      it('revert of caller is neither owner nor operator and has no allowance', async function () {
        const tx = this.mock.connect(this.other).requestRedeem(shares, this.controller, this.owner);

        await expect(tx)
          .to.be.revertedWithCustomError(this.mock, 'ERC20InsufficientAllowance')
          .withArgs(this.other, 0n, shares);
      });

      it('accumulates pending across multiple requests', async function () {
        await this.mock.connect(this.owner).requestRedeem(17n, this.controller, this.owner);
        await this.mock.connect(this.owner).requestRedeem(42n, this.controller, this.owner);

        await expect(this.mock.pendingRedeemRequest(0n, this.controller)).to.eventually.equal(17n + 42n);
      });
    });

    describe('fulfillRedeem', function () {
      beforeEach(async function () {
        await this.mock.connect(this.owner).requestRedeem(shares, this.controller, this.owner);
      });

      it('transitions pending to claimable and emits RedeemClaimable', async function () {
        const assetsBefore = await this.mock.totalAssets();
        const supplyBefore = await this.mock.totalSupply();

        await expect(this.mock.pendingRedeemRequest(0n, this.controller)).to.eventually.equal(shares);
        await expect(this.mock.claimableRedeemRequest(0n, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxWithdraw(this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxRedeem(this.controller)).to.eventually.equal(0n);

        await expect(this.mock.$_fulfillRedeem(shares, assets, this.controller))
          .to.emit(this.mock, 'RedeemClaimable')
          .withArgs(this.controller, 0n, assets, shares);

        await expect(this.mock.totalAssets()).to.eventually.equal(assetsBefore);
        await expect(this.mock.totalSupply()).to.eventually.equal(supplyBefore);

        await expect(this.mock.pendingRedeemRequest(0n, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.claimableRedeemRequest(0n, this.controller)).to.eventually.equal(shares);
        await expect(this.mock.maxWithdraw(this.controller)).to.eventually.equal(assets);
        await expect(this.mock.maxRedeem(this.controller)).to.eventually.equal(shares);
      });

      it('supports admin-determined asset ratio', async function () {
        await expect(this.mock.pendingRedeemRequest(0n, this.controller)).to.eventually.equal(shares);
        await expect(this.mock.claimableRedeemRequest(0n, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxWithdraw(this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxRedeem(this.controller)).to.eventually.equal(0n);

        await expect(this.mock.$_fulfillRedeem(shares, 42n, this.controller))
          .to.emit(this.mock, 'RedeemClaimable')
          .withArgs(this.controller, 0n, 42n, shares);

        await expect(this.mock.pendingRedeemRequest(0n, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.claimableRedeemRequest(0n, this.controller)).to.eventually.equal(shares);
        await expect(this.mock.maxWithdraw(this.controller)).to.eventually.equal(42n);
        await expect(this.mock.maxRedeem(this.controller)).to.eventually.equal(shares);
      });

      it('can be partially fulfilled', async function () {
        await expect(this.mock.pendingRedeemRequest(0n, this.controller)).to.eventually.equal(shares);
        await expect(this.mock.claimableRedeemRequest(0n, this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxWithdraw(this.controller)).to.eventually.equal(0n);
        await expect(this.mock.maxRedeem(this.controller)).to.eventually.equal(0n);

        await expect(this.mock.$_fulfillRedeem(42n, 17n, this.controller))
          .to.emit(this.mock, 'RedeemClaimable')
          .withArgs(this.controller, 0n, 17n, 42n);

        await expect(this.mock.pendingRedeemRequest(0n, this.controller)).to.eventually.equal(shares - 42n);
        await expect(this.mock.claimableRedeemRequest(0n, this.controller)).to.eventually.equal(42n);
        await expect(this.mock.maxWithdraw(this.controller)).to.eventually.equal(17n);
        await expect(this.mock.maxRedeem(this.controller)).to.eventually.equal(42n);
      });

      it('reverts when fulfilling more than pending', async function () {
        await expect(this.mock.$_fulfillRedeem(shares + 1n, assets, this.controller))
          .to.be.revertedWithCustomError(this.mock, 'ERC7540RedeemInsufficientPendingShares')
          .withArgs(shares + 1n, shares);
      });
    });

    describe('claim', function () {
      beforeEach(async function () {
        await this.mock.connect(this.owner).requestRedeem(shares, this.controller, this.owner);
        await this.mock.$_fulfillRedeem(shares, assets, this.controller);
      });

      describe('via redeem()', function () {
        it('transfers tokens to receiver and emits Withdraw', async function () {
          await expect(this.mock.pendingRedeemRequest(0n, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableRedeemRequest(0n, this.controller)).to.eventually.equal(shares);
          await expect(this.mock.maxRedeem(this.controller)).to.eventually.equal(shares);

          const assetsBefore = await this.mock.totalAssets();
          const supplyBefore = await this.mock.totalSupply();

          const tx = this.mock.connect(this.controller).redeem(shares, this.receiver, this.controller);

          await expect(tx)
            .to.emit(this.mock, 'Withdraw')
            .withArgs(this.controller, this.receiver, this.controller, assets, shares);
          await expect(tx).to.changeTokenBalances(this.token, [this.mock, this.receiver], [-assets, assets]);

          await expect(this.mock.pendingRedeemRequest(0n, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableRedeemRequest(0n, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.maxRedeem(this.controller)).to.eventually.equal(0n);
          await expect(this.mock.totalAssets()).to.eventually.equal(assetsBefore - assets);
          await expect(this.mock.totalSupply()).to.eventually.equal(supplyBefore - shares);
        });

        it('operator can trigger redeem on behalf of controller', async function () {
          const tx = this.mock.connect(this.operator).redeem(shares, this.receiver, this.controller);

          await expect(tx)
            .to.emit(this.mock, 'Withdraw')
            .withArgs(this.operator, this.receiver, this.controller, assets, shares);
          await expect(tx).to.changeTokenBalances(this.token, [this.mock, this.receiver], [-assets, assets]);
        });

        it('reverts when caller is neither owner nor operator of owner', async function () {
          await expect(this.mock.connect(this.other).redeem(shares, this.receiver, this.controller))
            .to.be.revertedWithCustomError(this.mock, 'ERC7540InvalidOperator')
            .withArgs(this.controller, this.other);
        });
      });

      describe('via withdraw()', function () {
        it('transfers exactly the requested tokens and emits Withdraw', async function () {
          await expect(this.mock.pendingRedeemRequest(0n, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableRedeemRequest(0n, this.controller)).to.eventually.equal(shares);
          await expect(this.mock.maxWithdraw(this.controller)).to.eventually.equal(assets);

          const assetsBefore = await this.mock.totalAssets();
          const supplyBefore = await this.mock.totalSupply();

          const tx = this.mock.connect(this.controller).withdraw(assets, this.receiver, this.controller);

          await expect(tx)
            .to.emit(this.mock, 'Withdraw')
            .withArgs(this.controller, this.receiver, this.controller, assets, shares);
          await expect(tx).to.changeTokenBalances(this.token, [this.mock, this.receiver], [-assets, assets]);

          await expect(this.mock.pendingRedeemRequest(0n, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.claimableRedeemRequest(0n, this.controller)).to.eventually.equal(0n);
          await expect(this.mock.maxWithdraw(this.controller)).to.eventually.equal(0n);
          await expect(this.mock.totalAssets()).to.eventually.equal(assetsBefore - assets);
          await expect(this.mock.totalSupply()).to.eventually.equal(supplyBefore - shares);
        });

        it('operator can trigger withdraw on behalf of controller', async function () {
          const tx = this.mock.connect(this.operator).withdraw(assets, this.receiver, this.controller);

          await expect(tx)
            .to.emit(this.mock, 'Withdraw')
            .withArgs(this.operator, this.receiver, this.controller, assets, shares);
          await expect(tx).to.changeTokenBalances(this.token, [this.mock, this.receiver], [-assets, assets]);
        });

        it('reverts when caller is neither owner nor operator of owner', async function () {
          await expect(this.mock.connect(this.other).withdraw(assets, this.receiver, this.controller))
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
