const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const name = 'My Token';
const symbol = 'MTKN';
const initialSupply = 100n;

async function fixture() {
  const [holder, recipient, approved] = await ethers.getSigners();

  const token = await ethers.deployContract('$ERC20Freezable', [name, symbol]);
  await token.$_mint(holder, initialSupply);

  return { holder, recipient, approved, token };
}

describe('ERC20Freezable', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('freeze management', function () {
    it('returns zero frozen balance for new users', async function () {
      await expect(this.token.frozen(this.holder)).to.eventually.equal(0);
    });

    it('returns full balance as available for unfrozen users', async function () {
      await expect(this.token.available(this.holder)).to.eventually.equal(initialSupply);
    });

    it('allows setting frozen amount', async function () {
      const frozenAmount = 50n;
      await this.token.$_setFrozen(this.holder, frozenAmount);

      await expect(this.token.frozen(this.holder)).to.eventually.equal(frozenAmount);
      await expect(this.token.available(this.holder)).to.eventually.equal(initialSupply - frozenAmount);
    });

    it('allows updating frozen amount', async function () {
      const firstAmount = 30n;
      const secondAmount = 70n;

      await this.token.$_setFrozen(this.holder, firstAmount);
      await expect(this.token.frozen(this.holder)).to.eventually.equal(firstAmount);

      await this.token.$_setFrozen(this.holder, secondAmount);
      await expect(this.token.frozen(this.holder)).to.eventually.equal(secondAmount);
      await expect(this.token.available(this.holder)).to.eventually.equal(initialSupply - secondAmount);
    });

    it('allows unfreezing by setting frozen amount to zero', async function () {
      const frozenAmount = 60n;
      await this.token.$_setFrozen(this.holder, frozenAmount);
      await this.token.$_setFrozen(this.holder, 0n);

      await expect(this.token.frozen(this.holder)).to.eventually.equal(0);
      await expect(this.token.available(this.holder)).to.eventually.equal(initialSupply);
    });

    it('emits Frozen event when setting frozen amount', async function () {
      const frozenAmount = 40n;
      await expect(this.token.$_setFrozen(this.holder, frozenAmount))
        .to.emit(this.token, 'Frozen')
        .withArgs(this.holder, frozenAmount);
    });
  });

  describe('freezable token operations', function () {
    describe('transfer', function () {
      it('allows transfer when no tokens are frozen', async function () {
        await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply)).to.changeTokenBalances(
          this.token,
          [this.holder, this.recipient],
          [-initialSupply, initialSupply],
        );
      });

      it('allows transfer when sufficient unfrozen balance available', async function () {
        const frozenAmount = 30n;
        const transferAmount = 50n;
        await this.token.$_setFrozen(this.holder, frozenAmount);

        await expect(this.token.connect(this.holder).transfer(this.recipient, transferAmount)).to.changeTokenBalances(
          this.token,
          [this.holder, this.recipient],
          [-transferAmount, transferAmount],
        );
      });

      it('reverts when trying to transfer more than available unfrozen balance', async function () {
        const frozenAmount = 60n;
        const transferAmount = 50n; // Available: 100 - 60 = 40, trying to transfer 50

        await this.token.$_setFrozen(this.holder, frozenAmount);

        await expect(this.token.connect(this.holder).transfer(this.recipient, transferAmount))
          .to.be.revertedWithCustomError(this.token, 'ERC20InsufficientUnfrozenBalance')
          .withArgs(this.holder, transferAmount, initialSupply - frozenAmount);
      });

      it('reverts when trying to transfer entire balance with some tokens frozen', async function () {
        const frozenAmount = 1n;
        await this.token.$_setFrozen(this.holder, frozenAmount);

        await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply))
          .to.be.revertedWithCustomError(this.token, 'ERC20InsufficientUnfrozenBalance')
          .withArgs(this.holder, initialSupply, initialSupply - frozenAmount);
      });

      it('allows transfer after unfreezing tokens', async function () {
        const frozenAmount = 60n;
        await this.token.$_setFrozen(this.holder, frozenAmount);
        await this.token.$_setFrozen(this.holder, 0n); // Unfreeze

        await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply)).to.changeTokenBalances(
          this.token,
          [this.holder, this.recipient],
          [-initialSupply, initialSupply],
        );
      });
    });

    describe('transfer from', function () {
      const allowance = 40n;

      beforeEach(async function () {
        await this.token.connect(this.holder).approve(this.approved, allowance);
      });

      it('allows transferFrom when sufficient unfrozen balance available', async function () {
        const frozenAmount = 20n;
        await this.token.$_setFrozen(this.holder, frozenAmount);

        await expect(
          this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance),
        ).to.changeTokenBalances(this.token, [this.holder, this.recipient], [-allowance, allowance]);
      });

      it('reverts when trying to transferFrom more than available unfrozen balance', async function () {
        const frozenAmount = 70n; // Available: 100 - 70 = 30, trying to transfer 40
        await this.token.$_setFrozen(this.holder, frozenAmount);

        await expect(this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance))
          .to.be.revertedWithCustomError(this.token, 'ERC20InsufficientUnfrozenBalance')
          .withArgs(this.holder, allowance, initialSupply - frozenAmount);
      });

      it('allows transferFrom after unfreezing sufficient tokens', async function () {
        const frozenAmount = 70n;
        await this.token.$_setFrozen(this.holder, frozenAmount);
        await this.token.$_setFrozen(this.holder, 20n); // Reduce frozen amount

        await expect(
          this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance),
        ).to.changeTokenBalances(this.token, [this.holder, this.recipient], [-allowance, allowance]);
      });
    });

    describe('mint', function () {
      const value = 42n;

      it('allows minting to any account (no freeze restrictions on minting)', async function () {
        const frozenAmount = 50n;
        await this.token.$_setFrozen(this.recipient, frozenAmount);

        await expect(this.token.$_mint(this.recipient, value)).to.changeTokenBalance(this.token, this.recipient, value);
      });

      it('updates available balance correctly after minting to frozen account', async function () {
        const frozenAmount = 30n;
        await this.token.$_setFrozen(this.recipient, frozenAmount);
        await this.token.$_mint(this.recipient, value);

        await expect(this.token.frozen(this.recipient)).to.eventually.equal(frozenAmount);
        await expect(this.token.available(this.recipient)).to.eventually.equal(value - frozenAmount); // 42 - 30 = 12
      });
    });

    describe('burn', function () {
      const value = 42n;

      it('allows burning when sufficient unfrozen balance available', async function () {
        const frozenAmount = 20n;
        await this.token.$_setFrozen(this.holder, frozenAmount);

        await expect(this.token.$_burn(this.holder, value)).to.changeTokenBalance(this.token, this.holder, -value);
      });

      it('reverts when trying to burn more than available unfrozen balance', async function () {
        const frozenAmount = 70n; // Available: 100 - 70 = 30, trying to burn 42
        await this.token.$_setFrozen(this.holder, frozenAmount);

        await expect(this.token.$_burn(this.holder, value))
          .to.be.revertedWithCustomError(this.token, 'ERC20InsufficientUnfrozenBalance')
          .withArgs(this.holder, value, initialSupply - frozenAmount);
      });

      it('allows burning entire unfrozen balance', async function () {
        const frozenAmount = 30n;
        const availableBalance = initialSupply - frozenAmount;
        await this.token.$_setFrozen(this.holder, frozenAmount);

        await expect(this.token.$_burn(this.holder, availableBalance)).to.changeTokenBalance(
          this.token,
          this.holder,
          -availableBalance,
        );
      });

      it('updates available balance correctly after burning', async function () {
        const frozenAmount = 40n;
        const burnAmount = 30n;
        await this.token.$_setFrozen(this.holder, frozenAmount);
        await this.token.$_burn(this.holder, burnAmount);

        await expect(this.token.frozen(this.holder)).to.eventually.equal(frozenAmount);
        await expect(this.token.available(this.holder)).to.eventually.equal(initialSupply - frozenAmount - burnAmount);
      });
    });

    describe('approve', function () {
      const allowance = 40n;

      it('allows approval with frozen tokens (approvals are not restricted)', async function () {
        const frozenAmount = 80n;
        await this.token.$_setFrozen(this.holder, frozenAmount);

        await this.token.connect(this.holder).approve(this.approved, allowance);
        await expect(this.token.allowance(this.holder, this.approved)).to.eventually.equal(allowance);
      });

      it('allows approval even when all tokens are frozen', async function () {
        await this.token.$_setFrozen(this.holder, initialSupply);

        await this.token.connect(this.holder).approve(this.approved, allowance);
        await expect(this.token.allowance(this.holder, this.approved)).to.eventually.equal(allowance);
      });
    });
  });

  describe('edge cases', function () {
    it('handles frozen amount greater than balance gracefully', async function () {
      const frozenAmount = initialSupply + 50n;
      await this.token.$_setFrozen(this.holder, frozenAmount);

      await expect(this.token.frozen(this.holder)).to.eventually.equal(frozenAmount);
      await expect(this.token.available(this.holder)).to.eventually.equal(0); // Should not underflow
    });

    it('prevents any transfer when frozen amount exceeds balance', async function () {
      const frozenAmount = initialSupply + 50n;
      await this.token.$_setFrozen(this.holder, frozenAmount);

      await expect(this.token.connect(this.holder).transfer(this.recipient, 1n))
        .to.be.revertedWithCustomError(this.token, 'ERC20InsufficientUnfrozenBalance')
        .withArgs(this.holder, 1n, 0);
    });
  });
});
