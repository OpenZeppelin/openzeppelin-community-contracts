const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { mapValues } = require('@openzeppelin/contracts/test/helpers/iterate');

// Mask helpers
const toHexString = i => '0x' + i.toString(16).padStart(64, 0);
const toMask = i => toHexString(1n << BigInt(i));
const combine = (...masks) => toHexString(masks.reduce((acc, m) => acc | BigInt(m), 0n));

const Roles = { admin: 0x00, public: 0xff };
const Masks = mapValues(Roles, toMask);

async function fixture() {
  const [admin, user, target, other] = await ethers.getSigners();

  const authority = await ethers.deployContract('$AccessManagerLight', [admin]);

  return {
    admin,
    user,
    target,
    other,
    authority,
  };
}

describe('AccessManaged', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('Permission Manager', function () {
    const selector = ethers.hexlify(ethers.randomBytes(4));
    const group = 17n;
    const adminGroup = 42n;
    const groups = [13n, 69n, 128n];

    describe('canCall', function () {
      describe('simple case: one group', async function () {
        it('Requirements set and Permissions set', async function () {
          this.withRequirements = true;
          this.withPermission = true;
        });

        it('Requirements set and Permissions not set', async function () {
          this.withRequirements = true;
          this.withPermission = false;
        });

        it('Requirements not set and Permissions set', async function () {
          this.withRequirements = false;
          this.withPermission = true;
        });

        it('Requirements not set and Permissions not set', async function () {
          this.withRequirements = false;
          this.withPermission = false;
        });

        afterEach(async function () {
          if (this.withRequirements) {
            await this.authority.setRequirements(this.target, [selector], [group]);
          }
          if (this.withPermission) {
            await this.authority.addGroup(this.user, group);
          }
          await expect(this.authority.canCall(this.user, this.target, selector)).to.eventually.equal(
            this.withRequirements && this.withPermission,
          );
        });
      });

      describe('complexe case: one of many groups', async function () {
        it('some intersection', async function () {
          this.userGroups = [32, 42, 94, 128]; // User has all these groups
          this.targetGroups = [17, 35, 42, 69, 91]; // Target accepts any of these groups
        });

        it('no intersection', async function () {
          this.userGroups = [32, 50, 94, 128]; // User has all these groups
          this.targetGroups = [17, 35, 42, 69, 91]; // Target accepts any of these groups
        });

        afterEach(async function () {
          // set permissions and requirements
          await Promise.all([
            this.authority.setRequirements(this.target, [selector], this.targetGroups),
            ...this.userGroups.map(group => this.authority.addGroup(this.user, group)),
          ]);

          // check can call
          await expect(this.authority.canCall(this.user, this.target, selector)).to.eventually.equal(
            this.userGroups.some(g => this.targetGroups.includes(g)),
          );
        });
      });
    });

    describe('addGroup', function () {
      it('authorized', async function () {
        await expect(this.authority.connect(this.admin).addGroup(this.user, group))
          .to.emit(this.authority, 'GroupAdded')
          .withArgs(this.user, group);
      });

      it('restricted', async function () {
        await expect(this.authority.connect(this.other).addGroup(this.user, group))
          .to.revertedWithCustomError(this.authority, 'MissingPermissions')
          .withArgs(this.other, Masks.public, Masks.admin);
      });

      it('with role admin', async function () {
        await this.authority.connect(this.admin).addGroup(this.other, adminGroup);

        await expect(this.authority.connect(this.other).addGroup(this.user, group))
          .to.revertedWithCustomError(this.authority, 'MissingPermissions')
          .withArgs(this.other, combine(Masks.public, toMask(adminGroup)), Masks.admin);

        await expect(this.authority.setGroupAdmins(group, [adminGroup]))
          .to.emit(this.authority, 'GroupAdmins')
          .withArgs(group, toMask(adminGroup));

        await expect(this.authority.connect(this.other).addGroup(this.user, group))
          .to.emit(this.authority, 'GroupAdded')
          .withArgs(this.user, group);
      });

      it('effect', async function () {
        await expect(this.authority.getGroups(this.user)).to.eventually.equal(Masks.public);

        await expect(this.authority.connect(this.admin).addGroup(this.user, group))
          .to.emit(this.authority, 'GroupAdded')
          .withArgs(this.user, group);

        await expect(this.authority.getGroups(this.user)).to.eventually.equal(combine(Masks.public, toMask(group)));
      });
    });

    describe('remGroup', function () {
      beforeEach(async function () {
        await this.authority.connect(this.admin).addGroup(this.user, group);
      });

      it('authorized', async function () {
        await expect(this.authority.connect(this.admin).remGroup(this.user, group))
          .to.emit(this.authority, 'GroupRemoved')
          .withArgs(this.user, group);
      });

      it('restricted', async function () {
        await expect(this.authority.connect(this.other).remGroup(this.user, group))
          .to.revertedWithCustomError(this.authority, 'MissingPermissions')
          .withArgs(this.other, Masks.public, Masks.admin);
      });

      it('with role admin', async function () {
        await this.authority.connect(this.admin).addGroup(this.other, adminGroup);

        await expect(this.authority.connect(this.other).addGroup(this.user, group))
          .to.revertedWithCustomError(this.authority, 'MissingPermissions')
          .withArgs(this.other, combine(Masks.public, toMask(adminGroup)), Masks.admin);

        await expect(this.authority.setGroupAdmins(group, [adminGroup]))
          .to.emit(this.authority, 'GroupAdmins')
          .withArgs(group, toMask(adminGroup));

        await expect(this.authority.connect(this.other).remGroup(this.user, group))
          .to.emit(this.authority, 'GroupRemoved')
          .withArgs(this.user, group);
      });

      it('effect', async function () {
        await expect(this.authority.getGroups(this.user)).to.eventually.equal(combine(Masks.public, toMask(group)));

        await expect(this.authority.connect(this.admin).remGroup(this.user, group))
          .to.emit(this.authority, 'GroupRemoved')
          .withArgs(this.user, group);

        await expect(this.authority.getGroups(this.user)).to.eventually.equal(Masks.public);
      });
    });

    describe('setGroupAdmins', function () {
      it('authorized', async function () {
        await expect(this.authority.connect(this.admin).setGroupAdmins(group, groups))
          .to.emit(this.authority, 'GroupAdmins')
          .withArgs(group, combine(...groups.map(toMask)));
      });

      it('restricted', async function () {
        await expect(this.authority.connect(this.other).setGroupAdmins(group, groups))
          .to.revertedWithCustomError(this.authority, 'MissingPermissions')
          .withArgs(this.other, Masks.public, Masks.admin);
      });

      it('effect', async function () {
        // Set some previous value
        await this.authority.connect(this.admin).setGroupAdmins(group, [group]);

        // Check previous value is set
        await expect(this.authority.getGroupAdmins(group)).to.eventually.equal(combine(Masks.admin, toMask(group)));

        // Set some new values
        await expect(this.authority.connect(this.admin).setGroupAdmins(group, groups))
          .to.emit(this.authority, 'GroupAdmins')
          .withArgs(group, combine(...groups.map(toMask)));

        // Check the new values are set, and the previous is removed
        await expect(this.authority.getGroupAdmins(group)).to.eventually.equal(
          combine(Masks.admin, ...groups.map(toMask)),
        );
      });
    });

    describe('setRequirements', function () {
      it('authorized', async function () {
        await expect(this.authority.connect(this.admin).setRequirements(this.target, [selector], groups))
          .to.emit(this.authority, 'RequirementsSet')
          .withArgs(this.target, selector, combine(...groups.map(toMask)));
      });

      it('restricted', async function () {
        await expect(this.authority.connect(this.other).setRequirements(this.target, [selector], groups))
          .to.revertedWithCustomError(this.authority, 'MissingPermissions')
          .withArgs(this.other, Masks.public, Masks.admin);
      });

      it('effect', async function () {
        // Set some previous value
        await this.authority.connect(this.admin).setRequirements(this.target, [selector], [group]);

        // Check previous value is set
        await expect(this.authority.getRequirements(this.target, selector)).to.eventually.equal(
          combine(Masks.admin, toMask(group)),
        );

        // Set some new values
        await expect(this.authority.connect(this.admin).setRequirements(this.target, [selector], groups))
          .to.emit(this.authority, 'RequirementsSet')
          .withArgs(this.target, selector, combine(...groups.map(toMask)));

        // Check the new values are set, and the previous is removed
        await expect(this.authority.getRequirements(this.target, selector)).to.eventually.equal(
          combine(Masks.admin, ...groups.map(toMask)),
        );
      });
    });
  });
});
