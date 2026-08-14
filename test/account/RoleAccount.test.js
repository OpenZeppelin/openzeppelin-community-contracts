const { ethers } = require('hardhat');
const { expect } = require('chai');

// Note that most tests related to RoleAccount are in test/account/RoleAccountFactory.test.js
describe('RoleAccount', function () {
  it('should revert if called directly', async function () {
    const implementation = await ethers.deployContract('$RoleAccount');

    await expect(implementation.accessManager()).to.be.revertedWithCustomError(
      implementation,
      'RoleAccountDirectCallNotAllowed',
    );
    await expect(implementation.roleId()).to.be.revertedWithCustomError(
      implementation,
      'RoleAccountDirectCallNotAllowed',
    );
  });

  it('should revert if deployed via clones without immutable args', async function () {
    const factory = await ethers.deployContract('$Clones');
    const implementation = await ethers.deployContract('$RoleAccount');

    const signer = await factory.$clone.staticCall(implementation).then(address => implementation.attach(address));
    await factory.$clone(implementation);

    await expect(signer.accessManager()).to.be.revertedWithCustomError(signer, 'RoleAccountInvalidImmutableArgs');
    await expect(signer.roleId()).to.be.revertedWithCustomError(signer, 'RoleAccountInvalidImmutableArgs');
  });
});
