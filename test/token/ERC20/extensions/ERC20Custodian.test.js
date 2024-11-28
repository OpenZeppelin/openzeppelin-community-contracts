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
    });
  });
});
