const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const name = 'My Token';
const symbol = 'MTKN';
const initialSupply = 100n;

async function fixture() {
  const [holder, recipient, approved] = await ethers.getSigners();

  const token = await ethers.deployContract('$ERC20CustodianMock', [holder, name, symbol]);
  await token.$_mint(holder, initialSupply);

  return { holder, recipient, approved, token };
}

describe('ERC20CustodianMock', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('allowlist token', function () {
    describe('transfer', function () {
      it('allows to transfer with available balance', async function () {
        await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply)).to.changeTokenBalances(
          this.token,
          [this.holder, this.recipient],
          [-initialSupply, initialSupply],
        );
      });

      it('allows to transfer when frozen and then unfrozen', async function () {
        await this.token.freeze(this.holder, initialSupply);
        await this.token.freeze(this.holder, 0);

        await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply)).to.changeTokenBalances(
          this.token,
          [this.holder, this.recipient],
          [-initialSupply, initialSupply],
        );
      });

      it('reverts when trying to transfer when frozen', async function () {
        await this.token.freeze(this.holder, initialSupply);

        await expect(
          this.token.connect(this.holder).transfer(this.recipient, initialSupply),
        ).to.be.revertedWithCustomError(this.token, 'ERC20InsufficientUnfrozenBalance');
      });
    });

    describe('transfer from', function () {
      const allowance = 40n;

      beforeEach(async function () {
        await this.token.connect(this.holder).approve(this.approved, allowance);
      });

      it('allows to transfer with available balance', async function () {
        await expect(
          this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance),
        ).to.changeTokenBalances(this.token, [this.holder, this.recipient], [-allowance, allowance]);
      });

      it('allows to transfer when frozen and then unfrozen', async function () {
        await this.token.freeze(this.holder, allowance);
        await this.token.freeze(this.holder, 0);

        await expect(
          this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance),
        ).to.changeTokenBalances(this.token, [this.holder, this.recipient], [-allowance, allowance]);
      });

      it('reverts when trying to transfer when frozen', async function () {
        await this.token.freeze(this.holder, initialSupply);

        await expect(
          this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance),
        ).to.be.revertedWithCustomError(this.token, 'ERC20InsufficientUnfrozenBalance');
      });
    });

    describe('mint', function () {
      const value = 42n;

      it('allows to mint when unfrozen', async function () {
        await expect(this.token.$_mint(this.recipient, value)).to.changeTokenBalance(this.token, this.recipient, value);
      });
    });

    describe('burn', function () {
      const value = 42n;

      it('allows to burn when unfrozen', async function () {
        await expect(this.token.$_burn(this.holder, value)).to.changeTokenBalance(this.token, this.holder, -value);
      });

      it('allows to burn when frozen', async function () {
        await this.token.freeze(this.holder, value);
        await expect(this.token.$_burn(this.holder, value)).to.changeTokenBalance(this.token, this.holder, -value);
      });
    });

    describe('approve', function () {
      const allowance = 40n;

      it('allows to approve when unfrozen', async function () {
        await this.token.connect(this.holder).approve(this.approved, allowance);
        expect(await this.token.allowance(this.holder, this.approved)).to.equal(allowance);
      });

      it('allows to approve when frozen and then unfrozen', async function () {
        await this.token.freeze(this.holder, allowance);
        await this.token.freeze(this.holder, 0);

        await this.token.connect(this.holder).approve(this.approved, allowance);
        expect(await this.token.allowance(this.holder, this.approved)).to.equal(allowance);
      });

      it('allows to approve when frozen', async function () {
        await this.token.freeze(this.holder, allowance);
        await this.token.connect(this.holder).approve(this.approved, allowance);
        expect(await this.token.allowance(this.holder, this.approved)).to.equal(allowance);
      });
    });

    describe('freeze', function () {
      it('revert if not enough balance to freeze', async function () {
        await expect(this.token.freeze(this.holder, initialSupply + BigInt(1))).to.be.revertedWithCustomError(
          this.token,
          'ERC20InsufficientUnfrozenBalance',
        );
      });

      it('should allow reducing frozen amount', async function () {
        // First, freeze 80 tokens out of 100
        await this.token.freeze(this.holder, 80n);
        expect(await this.token.frozen(this.holder)).to.equal(80n);

        // Now reduce frozen amount to 50 (this should work with the fix)
        await this.token.freeze(this.holder, 50n);
        expect(await this.token.frozen(this.holder)).to.equal(50n);

        // Verify available balance is now 100 - 50 = 50
        expect(await this.token.availableBalance(this.holder)).to.equal(50n);
      });
    });

    describe('edge cases', function () {
      it('should revert when non-custodian tries to freeze', async function () {
        await expect(this.token.connect(this.recipient).freeze(this.holder, 50n)).to.be.revertedWithCustomError(
          this.token,
          'ERC20NotCustodian',
        );
      });

      it('should revert when trying to freeze zero address', async function () {
        await expect(this.token.freeze(ethers.ZeroAddress, 50n)).to.be.revertedWithCustomError(
          this.token,
          'ERC20InsufficientUnfrozenBalance',
        );
      });

      it('should allow freezing zero amount (complete unfreeze)', async function () {
        // First freeze some tokens
        await this.token.freeze(this.holder, 80n);
        expect(await this.token.frozen(this.holder)).to.equal(80n);

        // Then unfreeze completely by setting to 0
        await this.token.freeze(this.holder, 0n);
        expect(await this.token.frozen(this.holder)).to.equal(0n);
        expect(await this.token.availableBalance(this.holder)).to.equal(initialSupply);
      });

      it('should allow freezing exact balance amount', async function () {
        await this.token.freeze(this.holder, initialSupply);

        expect(await this.token.frozen(this.holder)).to.equal(initialSupply);
        expect(await this.token.availableBalance(this.holder)).to.equal(0n);

        // Should prevent any transfers
        await expect(this.token.connect(this.holder).transfer(this.recipient, 1n)).to.be.revertedWithCustomError(
          this.token,
          'ERC20InsufficientUnfrozenBalance',
        );
      });

      it('should allow partial transfers up to available balance', async function () {
        await this.token.freeze(this.holder, 70n); // Freeze 70, available = 30

        // Should allow transfer of exactly available amount
        await this.token.connect(this.holder).transfer(this.recipient, 30n);
        expect(await this.token.balanceOf(this.holder)).to.equal(70n);

        // Should prevent transfer of even 1 more token
        await expect(this.token.connect(this.holder).transfer(this.recipient, 1n)).to.be.revertedWithCustomError(
          this.token,
          'ERC20InsufficientUnfrozenBalance',
        );
      });

      it('should allow minting to accounts with frozen balance', async function () {
        await this.token.freeze(this.holder, 50n);

        // Mint 20 more tokens
        await this.token.$_mint(this.holder, 20n);

        expect(await this.token.balanceOf(this.holder)).to.equal(120n);
        expect(await this.token.frozen(this.holder)).to.equal(50n);
        expect(await this.token.availableBalance(this.holder)).to.equal(70n);
      });

      it('should respect frozen balance in transferFrom', async function () {
        const allowance = 50n;
        await this.token.connect(this.holder).approve(this.approved, allowance);
        await this.token.freeze(this.holder, 80n); // Available = 20

        // Should fail even with approval when trying to transfer more than available
        await expect(
          this.token.connect(this.approved).transferFrom(this.holder, this.recipient, 30n),
        ).to.be.revertedWithCustomError(this.token, 'ERC20InsufficientUnfrozenBalance');

        // Should work for available amount
        await this.token.connect(this.approved).transferFrom(this.holder, this.recipient, 20n);
        expect(await this.token.balanceOf(this.holder)).to.equal(80n);
      });

      it('should allow increasing frozen amount', async function () {
        await this.token.freeze(this.holder, 50n);
        expect(await this.token.availableBalance(this.holder)).to.equal(50n);

        // Increase frozen amount
        await this.token.freeze(this.holder, 80n);
        expect(await this.token.frozen(this.holder)).to.equal(80n);
        expect(await this.token.availableBalance(this.holder)).to.equal(20n);
      });

      it('should emit TokensFrozen event with correct parameters', async function () {
        await expect(this.token.freeze(this.holder, 50n))
          .to.emit(this.token, 'TokensFrozen')
          .withArgs(this.holder, 50n);
      });

      it('should handle accounts with zero balance', async function () {
        // Test with recipient who has 0 balance
        expect(await this.token.balanceOf(this.recipient)).to.equal(0n);

        // Should allow freezing 0 amount
        await this.token.freeze(this.recipient, 0n);
        expect(await this.token.frozen(this.recipient)).to.equal(0n);

        // Should revert when trying to freeze non-zero amount
        await expect(this.token.freeze(this.recipient, 1n)).to.be.revertedWithCustomError(
          this.token,
          'ERC20InsufficientUnfrozenBalance',
        );
      });

      it('should allow burning frozen tokens', async function () {
        await this.token.freeze(this.holder, 50n);

        // Burning should work even for frozen tokens
        await expect(this.token.$_burn(this.holder, 30n)).to.changeTokenBalance(this.token, this.holder, -30n);

        // Balance should now be 70, frozen still 50, available = 20
        expect(await this.token.balanceOf(this.holder)).to.equal(70n);
        expect(await this.token.frozen(this.holder)).to.equal(50n);
        expect(await this.token.availableBalance(this.holder)).to.equal(20n);
      });

      it('should handle multiple freeze operations correctly', async function () {
        // Start with multiple freeze operations
        await this.token.freeze(this.holder, 30n);
        await this.token.freeze(this.holder, 60n); // Increase
        await this.token.freeze(this.holder, 40n); // Decrease
        await this.token.freeze(this.holder, 0n); // Complete unfreeze

        expect(await this.token.frozen(this.holder)).to.equal(0n);
        expect(await this.token.availableBalance(this.holder)).to.equal(initialSupply);
      });
    });
  });
});
