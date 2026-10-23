import { network } from 'hardhat';
import { expect } from 'chai';

const {
  ethers,
  helpers: { time },
  networkHelpers: { loadFixture },
} = await network.create();

const name = 'My Token';
const symbol = 'MTKN';
const initialSupply = 100n;

async function fixture() {
  const [holder, recipient, approved] = await ethers.getSigners();

  const token = await ethers.deployContract('$ERC20CollateralMock', [3600, name, symbol]);
  await token.$_mint(holder, initialSupply);

  return { holder, recipient, approved, token };
}

describe('ERC20Collateral', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('amount', function () {
    const MAX_UINT128 = 2n ** 128n - 1n;

    it('mint all of collateral amount', async function () {
      await expect(this.token.$_mint(this.holder, MAX_UINT128 - initialSupply)).to.changeTokenBalance(
        ethers,
        this.token,
        this.holder,
        MAX_UINT128 - initialSupply,
      );
    });

    it('reverts when minting more than collateral amount', async function () {
      await expect(this.token.$_mint(this.holder, MAX_UINT128)).to.be.revertedWithCustomError(
        this.token,
        'ERC20ExceededSupply',
      );
    });
  });

  describe('expiration', function () {
    it('mint before expiration', async function () {
      await expect(this.token.$_mint(this.holder, initialSupply)).to.changeTokenBalance(
        ethers,
        this.token,
        this.holder,
        initialSupply,
      );
    });

    it('reverts when minting after expiration', async function () {
      await time.increaseBy.timestamp(await this.token.liveness());
      await expect(this.token.$_mint(this.holder, initialSupply)).to.be.revertedWithCustomError(
        this.token,
        'ERC20ExpiredCollateral',
      );
    });
  });
});
