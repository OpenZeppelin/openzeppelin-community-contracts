const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const name = 'My Token';
const symbol = 'MTKN';
const initialSupply = 100n;

async function fixture() {
  const [holder, recipient, approved] = await ethers.getSigners();

  const token = await ethers.deployContract('$ERC20Restricted', [name, symbol]);
  await token.$_mint(holder, initialSupply);

  return { holder, recipient, approved, token };
}

describe('ERC20Restricted', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('restriction management', function () {
    it('returns DEFAULT restriction for new users', async function () {
      await expect(this.token.getRestriction(this.holder)).to.eventually.equal(0); // DEFAULT
    });

    it('allows users with DEFAULT restriction', async function () {
      await expect(this.token.isUserAllowed(this.holder)).to.eventually.equal(true);
    });

    it('allows users with ALLOWED status', async function () {
      await this.token.$_allowUser(this.holder); // Sets to ALLOWED
      await expect(this.token.getRestriction(this.holder)).to.eventually.equal(2); // ALLOWED
      await expect(this.token.isUserAllowed(this.holder)).to.eventually.equal(true);
    });

    it('blocks users with BLOCKED status', async function () {
      await this.token.$_blockUser(this.holder); // Sets to BLOCKED
      await expect(this.token.getRestriction(this.holder)).to.eventually.equal(1); // BLOCKED
      await expect(this.token.isUserAllowed(this.holder)).to.eventually.equal(false);
    });

    it('resets user to DEFAULT restriction', async function () {
      await this.token.$_blockUser(this.holder); // Sets to BLOCKED
      await this.token.$_resetUser(this.holder); // Sets to DEFAULT
      await expect(this.token.getRestriction(this.holder)).to.eventually.equal(0); // DEFAULT
      await expect(this.token.isUserAllowed(this.holder)).to.eventually.equal(true);
    });

    it('emits UserRestrictionsUpdated event when restriction changes', async function () {
      await expect(this.token.$_blockUser(this.holder))
        .to.emit(this.token, 'UserRestrictionsUpdated')
        .withArgs(this.holder, 1); // BLOCKED

      await expect(this.token.$_allowUser(this.holder))
        .to.emit(this.token, 'UserRestrictionsUpdated')
        .withArgs(this.holder, 2); // ALLOWED

      await expect(this.token.$_resetUser(this.holder))
        .to.emit(this.token, 'UserRestrictionsUpdated')
        .withArgs(this.holder, 0); // DEFAULT
    });

    it('does not emit event when restriction is unchanged', async function () {
      await this.token.$_blockUser(this.holder); // Sets to BLOCKED
      await expect(this.token.$_blockUser(this.holder)).to.not.emit(this.token, 'UserRestrictionsUpdated');
    });
  });

  describe('restricted token operations', function () {
    describe('transfer', function () {
      it('allows transfer when sender and recipient have DEFAULT restriction', async function () {
        await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply)).to.changeTokenBalances(
          this.token,
          [this.holder, this.recipient],
          [-initialSupply, initialSupply],
        );
      });

      it('allows transfer when sender and recipient are ALLOWED', async function () {
        await this.token.$_allowUser(this.holder); // Sets to ALLOWED
        await this.token.$_allowUser(this.recipient); // Sets to ALLOWED

        await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply)).to.changeTokenBalances(
          this.token,
          [this.holder, this.recipient],
          [-initialSupply, initialSupply],
        );
      });

      it('reverts when sender is BLOCKED', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED

        await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply))
          .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
          .withArgs(this.holder);
      });

      it('reverts when recipient is BLOCKED', async function () {
        await this.token.$_blockUser(this.recipient); // Sets to BLOCKED

        await expect(this.token.connect(this.holder).transfer(this.recipient, initialSupply))
          .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
          .withArgs(this.recipient);
      });

      it('allows transfer when restricted user is then unrestricted', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED
        await this.token.$_resetUser(this.holder); // Sets back to DEFAULT

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

      it('allows transferFrom when sender and recipient are allowed', async function () {
        await expect(
          this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance),
        ).to.changeTokenBalances(this.token, [this.holder, this.recipient], [-allowance, allowance]);
      });

      it('reverts when sender is BLOCKED', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED

        await expect(this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance))
          .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
          .withArgs(this.holder);
      });

      it('reverts when recipient is BLOCKED', async function () {
        await this.token.$_blockUser(this.recipient); // Sets to BLOCKED

        await expect(this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance))
          .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
          .withArgs(this.recipient);
      });

      it('allows transferFrom when restricted user is then unrestricted', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED
        await this.token.$_allowUser(this.holder); // Sets to ALLOWED

        await expect(
          this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance),
        ).to.changeTokenBalances(this.token, [this.holder, this.recipient], [-allowance, allowance]);
      });
    });

    describe('mint', function () {
      const value = 42n;

      it('allows minting to DEFAULT users', async function () {
        await expect(this.token.$_mint(this.recipient, value)).to.changeTokenBalance(this.token, this.recipient, value);
      });

      it('allows minting to ALLOWED users', async function () {
        await this.token.$_allowUser(this.recipient); // Sets to ALLOWED

        await expect(this.token.$_mint(this.recipient, value)).to.changeTokenBalance(this.token, this.recipient, value);
      });

      it('reverts when trying to mint to BLOCKED user', async function () {
        await this.token.$_blockUser(this.recipient); // Sets to BLOCKED

        await expect(this.token.$_mint(this.recipient, value))
          .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
          .withArgs(this.recipient);
      });

      it('allows minting when restricted user is then unrestricted', async function () {
        await this.token.$_blockUser(this.recipient); // Sets to BLOCKED
        await this.token.$_resetUser(this.recipient); // Sets back to DEFAULT

        await expect(this.token.$_mint(this.recipient, value)).to.changeTokenBalance(this.token, this.recipient, value);
      });
    });

    describe('burn', function () {
      const value = 42n;

      it('allows burning from DEFAULT users', async function () {
        await expect(this.token.$_burn(this.holder, value)).to.changeTokenBalance(this.token, this.holder, -value);
      });

      it('allows burning from ALLOWED users', async function () {
        await this.token.$_allowUser(this.holder); // Sets to ALLOWED

        await expect(this.token.$_burn(this.holder, value)).to.changeTokenBalance(this.token, this.holder, -value);
      });

      it('reverts when trying to burn from BLOCKED user', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED

        await expect(this.token.$_burn(this.holder, value))
          .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
          .withArgs(this.holder);
      });

      it('allows burning when restricted user is then unrestricted', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED
        await this.token.$_allowUser(this.holder); // Sets to ALLOWED

        await expect(this.token.$_burn(this.holder, value)).to.changeTokenBalance(this.token, this.holder, -value);
      });
    });

    describe('approve', function () {
      const allowance = 40n;

      it('allows approval from DEFAULT users', async function () {
        await this.token.connect(this.holder).approve(this.approved, allowance);
        await expect(this.token.allowance(this.holder, this.approved)).to.eventually.equal(allowance);
      });

      it('allows approval from ALLOWED users', async function () {
        await this.token.$_allowUser(this.holder); // Sets to ALLOWED

        await this.token.connect(this.holder).approve(this.approved, allowance);
        await expect(this.token.allowance(this.holder, this.approved)).to.eventually.equal(allowance);
      });

      it('allows approval from BLOCKED users (approvals are not restricted)', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED

        await this.token.connect(this.holder).approve(this.approved, allowance);
        await expect(this.token.allowance(this.holder, this.approved)).to.eventually.equal(allowance);
      });
    });
  });
});
