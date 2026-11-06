const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture, time } = require('@nomicfoundation/hardhat-network-helpers');
const {
  shouldSupportInterfaces,
} = require('@openzeppelin/contracts/test/utils/introspection/SupportsInterface.behavior');

const name = 'My Token';
const symbol = 'MTKN';
const initialSupply = 100n;

const UNIT = ethers.WeiPerEther;

async function fixture() {
  const [holder, recipient] = await ethers.getSigners();

  const token = await ethers.deployContract('$ERC20ScaledUIAmount', [name, symbol]);
  await token.$_mint(holder, initialSupply);

  return { holder, recipient, token };
}

describe('ERC20ScaledUIAmount', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldSupportInterfaces({
    ScaledUIAmount: ['uiMultiplier()'],
    ScaledUIAmountNewUIMultiplier: ['newUIMultiplier()', 'effectiveAt()'],
    ScaledUIAmountConversion: ['toUIAmount(uint256)', 'fromUIAmount(uint256)'],
    ScaledUIAmountBalances: ['balanceOfUI(address)', 'totalSupplyUI()'],
  });

  it('matches the ERC-8056 interface identifiers', async function () {
    for (const interfaceId of ['0xa60bf13d', '0x4bd27648', '0x57854fc3', '0xd890fd71']) {
      await expect(this.token.supportsInterface(interfaceId)).to.eventually.be.true;
    }
  });

  describe('initial state', function () {
    it('uses a multiplier of 1.0', async function () {
      await expect(this.token.uiMultiplier()).to.eventually.equal(UNIT);
      await expect(this.token.newUIMultiplier()).to.eventually.equal(UNIT);
      await expect(this.token.effectiveAt()).to.eventually.equal(0n);
    });

    it('reports UI amounts equal to raw amounts', async function () {
      await expect(this.token.balanceOfUI(this.holder)).to.eventually.equal(initialSupply);
      await expect(this.token.totalSupplyUI()).to.eventually.equal(initialSupply);
    });
  });

  describe('_setUIMultiplier', function () {
    it('schedules an update', async function () {
      const effectiveAt = (await time.latest()) + 100;

      await expect(this.token.$_setUIMultiplier(2n * UNIT, effectiveAt))
        .to.emit(this.token, 'UIMultiplierUpdated')
        .withArgs(UNIT, 2n * UNIT, effectiveAt)
        .to.not.emit(this.token, 'UIMultiplierUpdateCancelled');

      await expect(this.token.uiMultiplier()).to.eventually.equal(UNIT);
      await expect(this.token.newUIMultiplier()).to.eventually.equal(2n * UNIT);
      await expect(this.token.effectiveAt()).to.eventually.equal(effectiveAt);
      await expect(this.token.balanceOfUI(this.holder)).to.eventually.equal(initialSupply);
    });

    it('applies the update at the effective timestamp', async function () {
      const effectiveAt = (await time.latest()) + 100;
      await this.token.$_setUIMultiplier(2n * UNIT, effectiveAt);

      await time.increaseTo(effectiveAt - 1);
      await expect(this.token.uiMultiplier()).to.eventually.equal(UNIT);

      await time.increaseTo(effectiveAt);
      await expect(this.token.uiMultiplier()).to.eventually.equal(2n * UNIT);
      await expect(this.token.balanceOfUI(this.holder)).to.eventually.equal(2n * initialSupply);
      await expect(this.token.totalSupplyUI()).to.eventually.equal(2n * initialSupply);
      await expect(this.token.balanceOf(this.holder)).to.eventually.equal(initialSupply);
    });

    it('applies the update immediately when scheduled for the current timestamp', async function () {
      const effectiveAt = (await time.latest()) + 1;
      await time.setNextBlockTimestamp(effectiveAt);

      await expect(this.token.$_setUIMultiplier(2n * UNIT, effectiveAt))
        .to.emit(this.token, 'UIMultiplierUpdated')
        .withArgs(UNIT, 2n * UNIT, effectiveAt);

      await expect(this.token.uiMultiplier()).to.eventually.equal(2n * UNIT);
    });

    it('records the effective multiplier as old multiplier', async function () {
      const first = (await time.latest()) + 100;
      await this.token.$_setUIMultiplier(2n * UNIT, first);
      await time.increaseTo(first);

      const second = first + 100;
      await expect(this.token.$_setUIMultiplier(3n * UNIT, second))
        .to.emit(this.token, 'UIMultiplierUpdated')
        .withArgs(2n * UNIT, 3n * UNIT, second)
        .to.not.emit(this.token, 'UIMultiplierUpdateCancelled');

      await expect(this.token.uiMultiplier()).to.eventually.equal(2n * UNIT);
      await time.increaseTo(second);
      await expect(this.token.uiMultiplier()).to.eventually.equal(3n * UNIT);
    });

    it('supersedes a pending update', async function () {
      const first = (await time.latest()) + 100;
      await this.token.$_setUIMultiplier(2n * UNIT, first);

      const second = first + 100;
      await expect(this.token.$_setUIMultiplier(3n * UNIT, second))
        .to.emit(this.token, 'UIMultiplierUpdateCancelled')
        .withArgs(2n * UNIT, first)
        .to.emit(this.token, 'UIMultiplierUpdated')
        .withArgs(UNIT, 3n * UNIT, second);

      await time.increaseTo(first);
      await expect(this.token.uiMultiplier()).to.eventually.equal(UNIT);
      await time.increaseTo(second);
      await expect(this.token.uiMultiplier()).to.eventually.equal(3n * UNIT);
    });

    it('reverts with a zero multiplier', async function () {
      const effectiveAt = (await time.latest()) + 100;
      await expect(this.token.$_setUIMultiplier(0n, effectiveAt))
        .to.be.revertedWithCustomError(this.token, 'ERC20ScaledUIAmountInvalidMultiplier')
        .withArgs(0n);
    });

    it('reverts with a past timestamp', async function () {
      const effectiveAt = await time.latest();
      await expect(this.token.$_setUIMultiplier(2n * UNIT, effectiveAt))
        .to.be.revertedWithCustomError(this.token, 'ERC20ScaledUIAmountInvalidEffectiveAt')
        .withArgs(effectiveAt);
    });
  });

  describe('_cancelUIMultiplierUpdate', function () {
    it('cancels a pending update', async function () {
      const effectiveAt = (await time.latest()) + 100;
      await this.token.$_setUIMultiplier(2n * UNIT, effectiveAt);

      await expect(this.token.$_cancelUIMultiplierUpdate())
        .to.emit(this.token, 'UIMultiplierUpdateCancelled')
        .withArgs(2n * UNIT, effectiveAt)
        .to.emit(this.token, 'return$_cancelUIMultiplierUpdate')
        .withArgs(true);

      await expect(this.token.newUIMultiplier()).to.eventually.equal(UNIT);
      await expect(this.token.effectiveAt()).to.eventually.equal(0n);

      await time.increaseTo(effectiveAt);
      await expect(this.token.uiMultiplier()).to.eventually.equal(UNIT);
    });

    it('does nothing without a pending update', async function () {
      await expect(this.token.$_cancelUIMultiplierUpdate())
        .to.emit(this.token, 'return$_cancelUIMultiplierUpdate')
        .withArgs(false)
        .to.not.emit(this.token, 'UIMultiplierUpdateCancelled');
    });

    it('does nothing once the update took effect', async function () {
      const effectiveAt = (await time.latest()) + 100;
      await this.token.$_setUIMultiplier(2n * UNIT, effectiveAt);
      await time.increaseTo(effectiveAt);

      await expect(this.token.$_cancelUIMultiplierUpdate()).to.not.emit(this.token, 'UIMultiplierUpdateCancelled');
      await expect(this.token.uiMultiplier()).to.eventually.equal(2n * UNIT);
    });
  });

  describe('conversion', function () {
    beforeEach(async function () {
      // 3-for-2 split
      const effectiveAt = (await time.latest()) + 1;
      await time.setNextBlockTimestamp(effectiveAt);
      await this.token.$_setUIMultiplier((3n * UNIT) / 2n, effectiveAt);
    });

    it('converts raw amounts to UI amounts rounding down', async function () {
      await expect(this.token.toUIAmount(100n)).to.eventually.equal(150n);
      await expect(this.token.toUIAmount(3n)).to.eventually.equal(4n);
    });

    it('converts UI amounts to raw amounts rounding down', async function () {
      await expect(this.token.fromUIAmount(150n)).to.eventually.equal(100n);
      await expect(this.token.fromUIAmount(5n)).to.eventually.equal(3n);
    });

    it('keeps transfers in raw amounts', async function () {
      await expect(this.token.connect(this.holder).transfer(this.recipient, 10n)).to.changeTokenBalances(
        this.token,
        [this.holder, this.recipient],
        [-10n, 10n],
      );
      await expect(this.token.balanceOfUI(this.recipient)).to.eventually.equal(15n);
    });
  });
});
