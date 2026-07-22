const { ethers } = require('hardhat');
const { expect } = require('chai');

// Note that most tests related to RoleSigner are in test/access/manager/AccessManagerWithRoleAccounts.test.js
describe('RoleSigner', function () {
  it('should revert if deployed with address(0) access manager', async function () {
    const factory = await ethers.getContractFactory('$RoleSigner');
    await expect(ethers.deployContract('$RoleSigner', [ethers.ZeroAddress, 0n])).to.be.revertedWithCustomError(
      factory,
      'InvalidAccessManager',
    );
  });

  it('should return the admin role if deployed via clones without immutable args', async function () {
    const [admin] = await ethers.getSigners();
    const manager = await ethers.deployContract('$AccessManager', [admin]);

    const factory = await ethers.deployContract('$Clones');
    const implementation = await ethers.deployContract('$RoleSigner', [manager, 0n]);

    const signer = await factory.$clone.staticCall(implementation).then(address => implementation.attach(address));
    await factory.$clone(implementation);

    await expect(signer.roleId()).to.eventually.equal(0n);
    await expect(signer.$_isUnrestrictedMember(admin)).to.eventually.be.true;
  });
});
