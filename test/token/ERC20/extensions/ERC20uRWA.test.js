const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const {
  shouldSupportInterfaces,
} = require('@openzeppelin/contracts/test/utils/introspection/SupportsInterface.behavior');

const name = 'My uRWA Token';
const symbol = 'uRWA';
const initialSupply = 100n;

async function fixture() {
  const [holder, recipient, approved, freezer, enforcer, other] = await ethers.getSigners();

  const token = await ethers.deployContract('$ERC20uRWAMock', [name, symbol, freezer.address, enforcer.address]);
  await token.$_mint(holder, initialSupply);

  return { holder, recipient, approved, freezer, enforcer, other, token };
}

describe('ERC20uRWA', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('ERC165', function () {
    shouldSupportInterfaces({
      ERC7943Fungible: [
        'canTransfer(address,address,uint256)',
        'getFrozenTokens(address)',
        'setFrozenTokens(address,uint256)',
        'forcedTransfer(address,address,uint256)',
        'canSend(address)',
        'canReceive(address)',
      ],
    });
  });

  describe('combined restriction and freezing', function () {
    it('allows transfer when user is allowed and has sufficient unfrozen balance', async function () {
      const transferAmount = 30n;

      await expect(this.token.connect(this.holder).transfer(this.recipient, transferAmount)).to.changeTokenBalances(
        this.token,
        [this.holder, this.recipient],
        [-transferAmount, transferAmount],
      );
    });

    it('reverts when sender is restricted', async function () {
      await this.token.$_blockUser(this.holder); // Sets to BLOCKED

      await expect(this.token.connect(this.holder).transfer(this.recipient, 30n))
        .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
        .withArgs(this.holder);
    });

    it('reverts when recipient is restricted', async function () {
      await this.token.$_blockUser(this.recipient); // Sets to BLOCKED

      await expect(this.token.connect(this.holder).transfer(this.recipient, 30n))
        .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
        .withArgs(this.recipient);
    });

    it('reverts when sender has insufficient unfrozen balance', async function () {
      const frozenAmount = 80n;
      const transferAmount = 30n; // Available: 100 - 80 = 20, trying to transfer 30

      await this.token.connect(this.freezer).setFrozenTokens(this.holder, frozenAmount);

      await expect(this.token.connect(this.holder).transfer(this.recipient, transferAmount))
        .to.be.revertedWithCustomError(this.token, 'ERC20InsufficientUnfrozenBalance')
        .withArgs(this.holder, transferAmount, initialSupply - frozenAmount);
    });

    it('allows transfer when both restrictions and freezing allow it', async function () {
      const frozenAmount = 20n;
      const transferAmount = 30n; // Available: 100 - 20 = 80, transferring 30

      await this.token.connect(this.freezer).setFrozenTokens(this.holder, frozenAmount);
      await this.token.$_allowUser(this.holder); // Sets to ALLOWED
      await this.token.$_allowUser(this.recipient); // Sets to ALLOWED

      await expect(this.token.connect(this.holder).transfer(this.recipient, transferAmount)).to.changeTokenBalances(
        this.token,
        [this.holder, this.recipient],
        [-transferAmount, transferAmount],
      );
    });
  });

  describe('canTransfer', function () {
    it('returns true when all conditions are met', async function () {
      const amount = 30n;
      await expect(this.token.canTransfer(this.holder, this.recipient, amount)).to.eventually.equal(true);
    });

    it('returns false when sender is restricted', async function () {
      await this.token.$_blockUser(this.holder); // Sets to BLOCKED

      await expect(this.token.canTransfer(this.holder, this.recipient, 30n)).to.eventually.equal(false);
    });

    it('returns false when recipient is restricted', async function () {
      await this.token.$_blockUser(this.recipient); // Sets to BLOCKED

      await expect(this.token.canTransfer(this.holder, this.recipient, 30n)).to.eventually.equal(false);
    });

    it('returns false when amount exceeds unfrozen balance but is within the total balance', async function () {
      const frozenAmount = 80n;
      const transferAmount = 30n; // Available: 100 - 80 = 20

      await this.token.connect(this.freezer).setFrozenTokens(this.holder, frozenAmount);

      await expect(this.token.canTransfer(this.holder, this.recipient, transferAmount)).to.eventually.equal(false);
    });

    it('returns true when amount exceeds the total balance', async function () {
      // Plain balance insufficiency is a base ERC-20 validation, not a permissioned rule.
      await expect(this.token.canTransfer(this.holder, this.recipient, initialSupply + 1n)).to.eventually.equal(true);
    });

    it('returns true for a zero-balance sender', async function () {
      await expect(this.token.canTransfer(this.other, this.recipient, 1n)).to.eventually.equal(true);
    });

    it('reflects canSend and canReceive overrides', async function () {
      await this.token.setSendDenied(this.holder, true);
      await expect(this.token.canTransfer(this.holder, this.recipient, 10n)).to.eventually.equal(false);
      await expect(this.token.canTransfer(this.recipient, this.holder, 10n)).to.eventually.equal(true);

      await this.token.setSendDenied(this.holder, false);
      await this.token.setReceiveDenied(this.recipient, true);
      await expect(this.token.canTransfer(this.holder, this.recipient, 10n)).to.eventually.equal(false);
    });
  });

  describe('canSend / canReceive enforcement', function () {
    it('reverts transfer when canSend returns false for the sender', async function () {
      await this.token.setSendDenied(this.holder, true);

      await expect(this.token.connect(this.holder).transfer(this.recipient, 10n))
        .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
        .withArgs(this.holder);
    });

    it('reverts transfer when canReceive returns false for the recipient', async function () {
      await this.token.setReceiveDenied(this.recipient, true);

      await expect(this.token.connect(this.holder).transfer(this.recipient, 10n))
        .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
        .withArgs(this.recipient);
    });

    it('allows one-way restrictions (can receive but not send)', async function () {
      await this.token.connect(this.holder).transfer(this.recipient, 10n);
      await this.token.setSendDenied(this.recipient, true);

      // recipient can still receive
      await expect(this.token.connect(this.holder).transfer(this.recipient, 10n)).to.changeTokenBalances(
        this.token,
        [this.holder, this.recipient],
        [-10n, 10n],
      );

      // but cannot send
      await expect(this.token.connect(this.recipient).transfer(this.holder, 5n))
        .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
        .withArgs(this.recipient);
    });
  });

  describe('freezing functionality', function () {
    describe('getFrozenTokens', function () {
      it('returns zero for users with no frozen tokens', async function () {
        await expect(this.token.getFrozenTokens(this.holder)).to.eventually.equal(0);
      });

      it('returns correct frozen amount', async function () {
        const frozenAmount = 40n;
        await this.token.connect(this.freezer).setFrozenTokens(this.holder, frozenAmount);

        await expect(this.token.getFrozenTokens(this.holder)).to.eventually.equal(frozenAmount);
      });
    });

    describe('setFrozenTokens', function () {
      it('allows freezer to set frozen amount', async function () {
        const frozenAmount = 50n;

        await expect(this.token.connect(this.freezer).setFrozenTokens(this.holder, frozenAmount))
          .to.emit(this.token, 'Frozen')
          .withArgs(this.holder, frozenAmount);

        await expect(this.token.frozen(this.holder)).to.eventually.equal(frozenAmount);
      });

      it('reverts when non-freezer tries to set frozen amount', async function () {
        await expect(this.token.connect(this.other).setFrozenTokens(this.holder, 50n)).to.be.revertedWithCustomError(
          this.token,
          'AccessControlUnauthorizedAccount',
        );
      });

      it('allows freezing more than the current balance for future balances withholding', async function () {
        const requestedFrozenAmount = initialSupply + 10n;

        await expect(this.token.connect(this.freezer).setFrozenTokens(this.holder, requestedFrozenAmount))
          .to.emit(this.token, 'Frozen')
          .withArgs(this.holder, requestedFrozenAmount);

        await expect(this.token.frozen(this.holder)).to.eventually.equal(requestedFrozenAmount);
        await expect(this.token.available(this.holder)).to.eventually.equal(0n);
      });

      it('withholds future incoming transfers when frozen exceeds balance', async function () {
        await this.token.connect(this.freezer).setFrozenTokens(this.recipient, 30n);
        await this.token.connect(this.holder).transfer(this.recipient, 20n);

        // recipient balance (20) is still fully covered by the frozen amount (30)
        await expect(this.token.available(this.recipient)).to.eventually.equal(0n);
        await expect(this.token.connect(this.recipient).transfer(this.holder, 1n))
          .to.be.revertedWithCustomError(this.token, 'ERC20InsufficientUnfrozenBalance')
          .withArgs(this.recipient, 1n, 0n);
      });

      it('allows freezer to update frozen amount', async function () {
        await this.token.connect(this.freezer).setFrozenTokens(this.holder, 30n);
        await this.token.connect(this.freezer).setFrozenTokens(this.holder, 70n);

        await expect(this.token.frozen(this.holder)).to.eventually.equal(70n);
      });

      it('allows freezer to unfreeze tokens', async function () {
        await this.token.connect(this.freezer).setFrozenTokens(this.holder, 60n);
        await this.token.connect(this.freezer).setFrozenTokens(this.holder, 0n);

        await expect(this.token.frozen(this.holder)).to.eventually.equal(0);
      });
    });
  });

  describe('force transfer functionality', function () {
    describe('forcedTransfer', function () {
      it('allows enforcer to force transfer', async function () {
        const transferAmount = 40n;

        const tx = this.token.connect(this.enforcer).forcedTransfer(this.holder, this.recipient, transferAmount);
        await expect(tx).to.emit(this.token, 'ForcedTransfer').withArgs(this.holder, this.recipient, transferAmount);
        await expect(tx).to.changeTokenBalances(
          this.token,
          [this.holder, this.recipient],
          [-transferAmount, transferAmount],
        );
      });

      it('reverts when non-enforcer tries to force transfer', async function () {
        await expect(
          this.token.connect(this.other).forcedTransfer(this.holder, this.recipient, 40n),
        ).to.be.revertedWithCustomError(this.token, 'AccessControlUnauthorizedAccount');
      });

      it('reverts when forcing transfer to restricted recipient', async function () {
        await this.token.$_blockUser(this.recipient); // Sets to BLOCKED

        await expect(this.token.connect(this.enforcer).forcedTransfer(this.holder, this.recipient, 40n))
          .to.be.revertedWithCustomError(this.token, 'ERC7943CannotReceive')
          .withArgs(this.recipient);
      });

      it('reverts when forcing transfer to a canReceive-denied recipient', async function () {
        await this.token.setReceiveDenied(this.recipient, true);

        await expect(this.token.connect(this.enforcer).forcedTransfer(this.holder, this.recipient, 40n))
          .to.be.revertedWithCustomError(this.token, 'ERC7943CannotReceive')
          .withArgs(this.recipient);
      });

      it('allows force transfer from a canSend-denied sender', async function () {
        const transferAmount = 40n;
        await this.token.setSendDenied(this.holder, true);

        await expect(
          this.token.connect(this.enforcer).forcedTransfer(this.holder, this.recipient, transferAmount),
        ).to.changeTokenBalances(this.token, [this.holder, this.recipient], [-transferAmount, transferAmount]);
      });

      it('allows force transfer from restricted sender', async function () {
        const transferAmount = 40n;
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED

        const tx = this.token.connect(this.enforcer).forcedTransfer(this.holder, this.recipient, transferAmount);
        await expect(tx).to.emit(this.token, 'ForcedTransfer').withArgs(this.holder, this.recipient, transferAmount);
        await expect(tx).to.changeTokenBalances(
          this.token,
          [this.holder, this.recipient],
          [-transferAmount, transferAmount],
        );
      });

      it('allows force transfer of frozen tokens', async function () {
        const frozenAmount = 60n;
        const transferAmount = 80n; // More than available (40), but should work with force transfer

        await this.token.connect(this.freezer).setFrozenTokens(this.holder, frozenAmount);

        const tx = this.token.connect(this.enforcer).forcedTransfer(this.holder, this.recipient, transferAmount);
        await expect(tx).to.emit(this.token, 'ForcedTransfer').withArgs(this.holder, this.recipient, transferAmount);
        await expect(tx).to.changeTokenBalances(
          this.token,
          [this.holder, this.recipient],
          [-transferAmount, transferAmount],
        );
      });

      it('emits a single Frozen event before the Transfer event when unfreezing', async function () {
        const transferAmount = 40n;
        await this.token.connect(this.freezer).setFrozenTokens(this.holder, initialSupply);

        const tx = await this.token.connect(this.enforcer).forcedTransfer(this.holder, this.recipient, transferAmount);
        const receipt = await tx.wait();
        const parsed = receipt.logs.map(log => this.token.interface.parseLog(log)).filter(Boolean);

        const frozenLogs = parsed.filter(log => log.name === 'Frozen');
        expect(frozenLogs).to.have.lengthOf(1);
        expect(frozenLogs[0].args).to.deep.equal([this.holder.address, initialSupply - transferAmount]);

        // EIP-7943: the Frozen event must precede the base token Transfer event.
        expect(parsed.findIndex(log => log.name === 'Frozen')).to.be.lessThan(
          parsed.findIndex(log => log.name === 'Transfer'),
        );
      });

      it('updates frozen balance when force transferring frozen tokens', async function () {
        const frozenAmount = 80n;
        const transferAmount = 70n;
        const expectedRemainingFrozen = initialSupply - transferAmount; // 100 - 70 = 30

        await this.token.connect(this.freezer).setFrozenTokens(this.holder, frozenAmount);
        await this.token.connect(this.enforcer).forcedTransfer(this.holder, this.recipient, transferAmount);

        await expect(this.token.frozen(this.holder)).to.eventually.equal(expectedRemainingFrozen);
      });

      it('does not update frozen balance when force transferring without affecting frozen tokens', async function () {
        const frozenAmount = 30n;
        const transferAmount = 20n; // Less than available (70)

        await this.token.connect(this.freezer).setFrozenTokens(this.holder, frozenAmount);
        await this.token.connect(this.enforcer).forcedTransfer(this.holder, this.recipient, transferAmount);

        await expect(this.token.frozen(this.holder)).to.eventually.equal(frozenAmount);
      });

      it('does not reduce the frozen balance when force transferring to self', async function () {
        const frozenAmount = initialSupply; // Fully frozen
        await this.token.connect(this.freezer).setFrozenTokens(this.holder, frozenAmount);

        // A forced transfer to self moves no tokens, so no frozen adjustment happens (it would
        // otherwise act as an unauthorized unfreeze bypassing the freezer role). It behaves as a
        // regular ERC-20 self-transfer, reverting when amount exceeds the unfrozen balance.
        await expect(this.token.connect(this.enforcer).forcedTransfer(this.holder, this.holder, frozenAmount))
          .to.be.revertedWithCustomError(this.token, 'ERC20InsufficientUnfrozenBalance')
          .withArgs(this.holder, frozenAmount, 0n);

        // The frozen balance is left untouched.
        await expect(this.token.frozen(this.holder)).to.eventually.equal(frozenAmount);
      });

      it('allows force transferring to self within the unfrozen balance without frozen adjustment', async function () {
        const frozenAmount = 60n;
        const transferAmount = 30n; // Available: 100 - 60 = 40
        await this.token.connect(this.freezer).setFrozenTokens(this.holder, frozenAmount);

        const tx = this.token.connect(this.enforcer).forcedTransfer(this.holder, this.holder, transferAmount);
        await expect(tx).to.emit(this.token, 'ForcedTransfer').withArgs(this.holder, this.holder, transferAmount);
        await expect(tx).to.changeTokenBalance(this.token, this.holder, 0n);
        await expect(this.token.frozen(this.holder)).to.eventually.equal(frozenAmount);
      });
    });
  });

  describe('minting and burning', function () {
    describe('mint', function () {
      const value = 42n;

      it('allows minting to allowed users', async function () {
        await expect(this.token.$_mint(this.recipient, value)).to.changeTokenBalance(this.token, this.recipient, value);
      });

      it('reverts when minting to restricted user', async function () {
        await this.token.$_blockUser(this.recipient); // Sets to BLOCKED

        await expect(this.token.$_mint(this.recipient, value))
          .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
          .withArgs(this.recipient);
      });

      it('allows minting to user with frozen tokens', async function () {
        await this.token.$_mint(this.recipient, 20n);
        await this.token.connect(this.freezer).setFrozenTokens(this.recipient, 20n);

        await expect(this.token.$_mint(this.recipient, value)).to.changeTokenBalance(this.token, this.recipient, value);
      });
    });

    describe('burn', function () {
      const value = 42n;

      it('allows burning from users with sufficient unfrozen balance', async function () {
        await expect(this.token.$_burn(this.holder, value)).to.changeTokenBalance(this.token, this.holder, -value);
      });

      it('reverts when burning from restricted user', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED

        await expect(this.token.$_burn(this.holder, value))
          .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
          .withArgs(this.holder);
      });

      it('reverts when burning more than unfrozen balance', async function () {
        const frozenAmount = 70n;
        await this.token.connect(this.freezer).setFrozenTokens(this.holder, frozenAmount);

        await expect(this.token.$_burn(this.holder, value))
          .to.be.revertedWithCustomError(this.token, 'ERC20InsufficientUnfrozenBalance')
          .withArgs(this.holder, value, initialSupply - frozenAmount);
      });
    });
  });

  describe('approval functionality', function () {
    const allowance = 40n;

    it('allows approval regardless of frozen or restricted status', async function () {
      await this.token.$_blockUser(this.holder); // Sets to BLOCKED
      await this.token.connect(this.freezer).setFrozenTokens(this.holder, 80n);

      await this.token.connect(this.holder).approve(this.approved, allowance);
      await expect(this.token.allowance(this.holder, this.approved)).to.eventually.equal(allowance);
    });

    describe('transferFrom with combined restrictions', function () {
      beforeEach(async function () {
        await this.token.connect(this.holder).approve(this.approved, allowance);
      });

      it('allows transferFrom when all conditions are met', async function () {
        await expect(
          this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance),
        ).to.changeTokenBalances(this.token, [this.holder, this.recipient], [-allowance, allowance]);
      });

      it('reverts transferFrom when sender is restricted', async function () {
        await this.token.$_blockUser(this.holder); // Sets to BLOCKED

        await expect(this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance))
          .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
          .withArgs(this.holder);
      });

      it('reverts transferFrom when recipient is restricted', async function () {
        await this.token.$_blockUser(this.recipient); // Sets to BLOCKED

        await expect(this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance))
          .to.be.revertedWithCustomError(this.token, 'ERC20UserRestricted')
          .withArgs(this.recipient);
      });

      it('reverts transferFrom when insufficient unfrozen balance', async function () {
        const frozenAmount = 70n; // Available: 100 - 70 = 30, trying to transfer 40
        await this.token.connect(this.freezer).setFrozenTokens(this.holder, frozenAmount);

        await expect(this.token.connect(this.approved).transferFrom(this.holder, this.recipient, allowance))
          .to.be.revertedWithCustomError(this.token, 'ERC20InsufficientUnfrozenBalance')
          .withArgs(this.holder, allowance, initialSupply - frozenAmount);
      });
    });
  });
});
