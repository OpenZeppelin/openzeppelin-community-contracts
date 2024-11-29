const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const name = 'My Token';
const symbol = 'MTKN';
const initialSupply = 100n;

async function fixture() {
  const [holder, recipient, approved] = await ethers.getSigners();

  const token = await ethers.deployContract('$ERC20Blocklist', [name, symbol]);
  await token.$_mint(holder, initialSupply);

  return { holder, recipient, approved, token };
}

describe('ERC20Blocklist', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('blocklist token', function () {
    describe('transfer', function () {
      it('allows to transfer when not blocked', async function () {
        await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply)).to.changeTokenBalances(
          this.token,
          [this.holder, this.recipient],
          [-initialSupply, initialSupply],
        );
      });

      it('allows to transfer when blocked and then unblocked', async function () {
        await this.token.$_blockUser(this.holder);
        await this.token.$_unblockUser(this.holder);

        await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply)).to.changeTokenBalances(
          this.token,
          [this.holder, this.recipient],
          [-initialSupply, initialSupply],
        );
      });

      it('reverts when trying to transfer when blocked', async function () {
        await this.token.$_blockUser(this.holder);

        await expect(
          this.token.connect(this.holder).transfer(this.recipient, initialSupply),
        ).to.be.revertedWithCustomError(this.token, 'ERC20Blocked');
      });
    });

    describe('transfer from', function () {
      const allowance = 40n;

      beforeEach(async function () {
        await this.token.connect(this.holder).approve(this.approved, allowance);
      });

      it('allows to transfer from when unblocked', async function () {
        await expect(
          this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance),
        ).to.changeTokenBalances(this.token, [this.holder, this.recipient], [-allowance, allowance]);
      });

      it('allows to transfer when blocked and then unblocked', async function () {
        await this.token.$_blockUser(this.holder);
        await this.token.$_unblockUser(this.holder);

        await expect(
          this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance),
        ).to.changeTokenBalances(this.token, [this.holder, this.recipient], [-allowance, allowance]);
      });

      it('reverts when trying to transfer from when blocked', async function () {
        await this.token.$_blockUser(this.holder);

        await expect(
          this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance),
        ).to.be.revertedWithCustomError(this.token, 'ERC20Blocked');
      });
    });

    describe('mint', function () {
      const value = 42n;

      it('allows to mint when unblocked', async function () {
        await expect(this.token.$_mint(this.recipient, value)).to.changeTokenBalance(this.token, this.recipient, value);
      });

      it('allows to mint when blocked and then unblocked', async function () {
        await this.token.$_blockUser(this.holder);
        await this.token.$_unblockUser(this.holder);

        await expect(this.token.$_mint(this.recipient, value)).to.changeTokenBalance(this.token, this.recipient, value);
      });

      it('reverts when trying to mint when blocked', async function () {
        await this.token.$_blockUser(this.recipient);

        await expect(this.token.$_mint(this.recipient, value)).to.be.revertedWithCustomError(
          this.token,
          'ERC20Blocked',
        );
      });
    });

    describe('burn', function () {
      const value = 42n;

      it('allows to burn when unblocked', async function () {
        await expect(this.token.$_burn(this.holder, value)).to.changeTokenBalance(this.token, this.holder, -value);
      });

      it('allows to burn when blocked and then unblocked', async function () {
        await this.token.$_blockUser(this.holder);
        await this.token.$_unblockUser(this.holder);

        await expect(this.token.$_burn(this.holder, value)).to.changeTokenBalance(this.token, this.holder, -value);
      });

      it('reverts when trying to burn when blocked', async function () {
        await this.token.$_blockUser(this.holder);

        await expect(this.token.$_burn(this.holder, value)).to.be.revertedWithCustomError(this.token, 'ERC20Blocked');
      });
    });

    describe('approve', function () {
      const allowance = 40n;

      it('allows to approve when unblocked', async function () {
        await this.token.connect(this.holder).approve(this.approved, allowance);
        expect(await this.token.allowance(this.holder, this.approved)).to.equal(allowance);
      });

      it('allows to approve when blocked and then unblocked', async function () {
        await this.token.$_blockUser(this.holder);
        await this.token.$_unblockUser(this.holder);

        await this.token.connect(this.holder).approve(this.approved, allowance);
        expect(await this.token.allowance(this.holder, this.approved)).to.equal(allowance);
      });

      it('reverts when trying to approve when blocked', async function () {
        await this.token.$_blockUser(this.holder);

        await expect(this.token.connect(this.holder).approve(this.approved, allowance)).to.be.revertedWithCustomError(
          this.token,
          'ERC20Blocked',
        );
      });
    });
  });
});
