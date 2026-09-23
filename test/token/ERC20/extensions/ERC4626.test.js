import { network } from 'hardhat';
import { shouldBehaveLikeERC4626Deposit, shouldBehaveLikeERC4626Redeem } from './ERC4626.behavior';

const {
  ethers,
  networkHelpers: { loadFixture },
} = await network.create();

const name = 'Vault Shares';
const symbol = 'vSHR';
const tokenName = 'Asset Token';
const tokenSymbol = 'AST';

async function fixture() {
  const token = await ethers.deployContract('$ERC20', [tokenName, tokenSymbol]);
  const mock = await ethers.deployContract('$ERC4626', [name, symbol, token]);
  return { token, mock };
}

describe('ERC4626 behavior is compatible with reference implementation', function () {
  before(async function () {
    Object.assign(this, { ethers });
  });

  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeERC4626Deposit({ isERC7540: false });
  shouldBehaveLikeERC4626Redeem({ isERC7540: false });
});
