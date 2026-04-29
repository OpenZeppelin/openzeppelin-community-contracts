const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { shouldBehaveLikeERC4626Redeem } = require('./ERC4626.behavior');
const { shouldBehaveLikeERC7540Operator, shouldBehaveLikeERC7540Deposit } = require('./ERC7540.behavior');
const { shouldBehaveLikeERC7575 } = require('./ERC7575.behavior');

const name = 'Vault Shares';
const symbol = 'vSHR';
const tokenName = 'Asset Token';
const tokenSymbol = 'AST';

async function fixture() {
  const token = await ethers.deployContract('$ERC20', [tokenName, tokenSymbol]);
  const mock = await ethers.deployContract('$ERC7540SyncRedeemMock', [name, symbol, token]);
  return { token, mock };
}

describe('ERC7540SyncRedeem', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));

    this.getRequestId = () => 0n;
    this.fulfillDeposit = (requestId, assets, shares, controller) =>
      this.mock.$_fulfillDeposit(assets, shares, controller);
    this.fulfillRedeem = () => {
      throw new Error('redeem is synchronous');
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

    it('reports async deposit and sync redeem', async function () {
      await expect(this.mock.$_isDepositAsync()).to.eventually.equal(true);
      await expect(this.mock.$_isRedeemAsync()).to.eventually.equal(false);
    });
  });

  shouldBehaveLikeERC7540Operator();
  shouldBehaveLikeERC7540Deposit({ supportCustomFulfill: true });
  shouldBehaveLikeERC4626Redeem({ isERC7540: true });
  shouldBehaveLikeERC7575();
});
