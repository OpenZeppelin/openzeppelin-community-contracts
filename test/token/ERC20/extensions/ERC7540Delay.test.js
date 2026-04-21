const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const time = require('@openzeppelin/contracts/test/helpers/time');
const {
  shouldBehaveLikeERC7540Operator,
  shouldBehaveLikeERC7540Deposit,
  shouldBehaveLikeERC7540Redeem,
} = require('./ERC7540.behavior');

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
      await expect(this.mock.depositDelay(this.owner)).to.eventually.equal(delay);
      await expect(this.mock.redeemDelay(this.owner)).to.eventually.equal(delay);
    });

    it('reports async deposit and redeem', async function () {
      await expect(this.mock.$_isDepositAsync()).to.eventually.equal(true);
      await expect(this.mock.$_isRedeemAsync()).to.eventually.equal(true);
    });
  });

  shouldBehaveLikeERC7540Operator();
  shouldBehaveLikeERC7540Deposit({ supportCustomFulfill: false });
  shouldBehaveLikeERC7540Redeem({ supportCustomFulfill: false });
});
