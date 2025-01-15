const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

async function fixture() {
  const [admin] = await ethers.getSigners();

  const implementation1 = await ethers.deployContract('UpgradeableImplementationMock', [1]);
  const implementation2 = await ethers.deployContract('UpgradeableImplementationMock', [2]);
  const implementation3 = await ethers.deployContract('UpgradeableImplementationMock', [3]);
  const beacon = await ethers.deployContract('UpgradeableBeacon', [implementation1, admin]);
  const proxy = await ethers
    .deployContract('HybridProxy', [beacon, '0x'])
    .then(({ target }) => implementation1.attach(target));

  return { admin, beacon, proxy, implementation1, implementation2, implementation3 };
}

describe('HybridProxy', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('setup at construction', async function () {
    const data = ethers.randomBytes(128);
    await expect(ethers.deployContract('HybridProxy', [this.beacon, data]))
      .to.be.revertedWithCustomError(this.implementation1, 'UnexpectedCall')
      .withArgs(this.admin, 0, data);
  });

  it('forwards calls', async function () {
    await expect(this.implementation1.attach(this.proxy).version()).to.eventually.equal(1);
  });

  it('beacon upgrade', async function () {
    await this.beacon.upgradeTo(this.implementation2);
    await expect(this.implementation1.attach(this.proxy).version()).to.eventually.equal(2);
  });

  it('decouple/recouple', async function () {
    await this.proxy.upgradeToAndCall(this.implementation3, '0x');
    await expect(this.implementation1.attach(this.proxy).version()).to.eventually.equal(3);

    // beacon updated no longer affect the upgrade process
    await this.beacon.upgradeTo(this.implementation2);
    await expect(this.implementation1.attach(this.proxy).version()).to.eventually.equal(3);

    // recouple to beacon
    await this.proxy.upgradeToAndCall(this.beacon, '0x');
    await expect(this.implementation1.attach(this.proxy).version()).to.eventually.equal(2);
  });
});
