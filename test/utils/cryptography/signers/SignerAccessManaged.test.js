import { network } from 'hardhat';
import { expect } from 'chai';

const {
  ethers,
  networkHelpers: { loadFixture },
} = await network.create();

const ROLE = 42n;

async function fixture() {
  const [admin] = await ethers.getSigners();

  const manager = await ethers.deployContract('$AccessManager', [admin]);
  const mock = await ethers.deployContract('$SignerAccessManaged', [manager, ROLE]);

  return { admin, manager, mock };
}

describe('SignerAccessManaged', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('exposes the access manager set in the constructor', async function () {
    await expect(this.mock.accessManager()).to.eventually.equal(this.manager);
  });

  it('exposes the role id set in the constructor', async function () {
    await expect(this.mock.roleId()).to.eventually.equal(ROLE);
  });
});
