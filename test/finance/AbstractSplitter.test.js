const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { sum } = require('@openzeppelin/contracts/test/helpers/math');

const amount = ethers.parseEther('1');

async function fixture() {
  const [owner, payee1, payee2, payee3] = await ethers.getSigners();

  const token = await ethers.deployContract('$ERC20Mock', ['name', 'symbol']);
  const mock = await ethers.deployContract('$PaymentSplitterMock', ['splitter name', 'splitter symbol', token]);

  return {
    owner,
    payee1,
    payee2,
    payee3,
    token,
    mock,
  };
}

describe('TokenizedERC20Splitter', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('set payee before receive', async function () {
    await this.mock.$_mint(this.payee1, 1);
    await this.token.$_mint(this.mock, amount);

    const tx = this.mock.release(this.payee1);
    await expect(tx).to.emit(this.mock, 'PaymentReleased').withArgs(this.payee1, amount);
    await expect(tx).to.changeTokenBalances(this.token, [this.mock, this.payee1], [-amount, amount]);
  });

  it('set payee after receive', async function () {
    await this.token.$_mint(this.mock, amount);
    await this.mock.$_mint(this.payee1, 1);

    const tx = this.mock.release(this.payee1);
    await expect(tx).to.emit(this.mock, 'PaymentReleased').withArgs(this.payee1, amount);
    await expect(tx).to.changeTokenBalances(this.token, [this.mock, this.payee1], [-amount, amount]);
  });

  it('multiple payees', async function () {
    const manifest = [
      { account: this.payee1, shares: 20n },
      { account: this.payee2, shares: 10n },
      { account: this.payee3, shares: 70n },
    ];
    const total = sum(...manifest.map(({ shares }) => shares));

    // setup
    await Promise.all(manifest.map(({ account, shares }) => this.mock.$_mint(account, shares)));
    await this.token.$_mint(this.mock, amount);

    // distribute to payees
    for (const { account, shares } of manifest) {
      const profit = (amount * shares) / total;

      await expect(this.mock.pendingRelease(account)).to.eventually.equal(profit);

      const tx = this.mock.release(account);
      await expect(tx).to.emit(this.mock, 'PaymentReleased').withArgs(account, profit);
      await expect(tx).to.changeTokenBalances(this.token, [this.mock, account], [-profit, profit]);
    }

    // check correct funds released accounting
    await expect(this.token.balanceOf(this.mock)).to.eventually.equal(0n);
  });

  it('multiple payees with varying shares', async function () {
    const manifest = Object.fromEntries(
      [
        { account: this.payee1, shares: 0n, pending: 0n },
        { account: this.payee2, shares: 0n, pending: 0n },
        { account: this.payee3, shares: 0n, pending: 0n },
      ].map(value => [value.account.address, value]),
    );

    const runCheck = () =>
      Promise.all(
        Object.values(manifest).map(async ({ account, shares, pending }) => {
          await expect(this.mock.balanceOf(account)).to.eventually.equal(shares);
          await expect(this.mock.pendingRelease(account)).to.eventually.equal(pending);
        }),
      );

    await runCheck();

    await this.mock.$_mint(this.payee1, 100n);
    await this.mock.$_mint(this.payee2, 100n);
    manifest[this.payee1.address].shares += 100n;
    manifest[this.payee2.address].shares += 100n;
    await runCheck();

    await this.token.$_mint(this.mock, 100n);
    manifest[this.payee1.address].pending += 50n; // 50% of 100
    manifest[this.payee2.address].pending += 50n; // 50% of 100
    await runCheck();

    await this.mock.$_mint(this.payee1, 100n);
    await this.mock.$_mint(this.payee3, 100n);
    manifest[this.payee1.address].shares += 100n;
    manifest[this.payee3.address].shares += 100n;
    await runCheck();

    await this.token.$_mint(this.mock, 100n);
    manifest[this.payee1.address].pending += 50n; // 50% of 100
    manifest[this.payee2.address].pending += 25n; // 25% of 100
    manifest[this.payee3.address].pending += 25n; // 25% of 100
    await runCheck();

    await this.mock.$_burn(this.payee1, 200n);
    manifest[this.payee1.address].shares -= 200n;
    await runCheck();

    await this.token.$_mint(this.mock, 100n);
    manifest[this.payee2.address].pending += 50n; // 50% of 100
    manifest[this.payee3.address].pending += 50n; // 50% of 100
    await runCheck();

    await this.mock.$_transfer(this.payee2, this.payee3, 40n);
    manifest[this.payee2.address].shares -= 40n;
    manifest[this.payee3.address].shares += 40n;
    await runCheck();

    await this.token.$_mint(this.mock, 100n);
    manifest[this.payee2.address].pending += 30n; // 30% of 100
    manifest[this.payee3.address].pending += 70n; // 70% of 100
    await runCheck();

    // do all releases
    for (const { account, pending } of Object.values(manifest)) {
      const tx = this.mock.release(account);
      await expect(tx).to.emit(this.mock, 'PaymentReleased').withArgs(account, pending);
      await expect(tx).to.changeTokenBalances(this.token, [this.mock, account], [-pending, pending]);
    }
  });
});
