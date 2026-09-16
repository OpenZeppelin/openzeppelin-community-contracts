const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');

function shouldBehaveLikeAccountERC6900() {
  describe('AccountERC6900', function () {
    beforeEach(async function () {
      await this.mock.deploy();
      await this.other.sendTransaction({ to: this.mock.target, value: ethers.parseEther('1') });

      this.modules = {};
      this.validationModule = await ethers.deployContract('$ERC6900ValidationMock');
      this.executionModule = await ethers.deployContract('$ERC6900ExecutionMock');
      this.randomContract = await ethers.deployContract('CallReceiverMock');

      this.mockFromEntrypoint = this.mock.connect(await impersonate(entrypoint.target));
    });

    describe('accountId', function () {
      it('should return the account ID', async function () {
        await expect(this.mock.accountId()).to.eventually.equal(
          '@openzeppelin/community-contracts.AccountERC6900.v0.0.0',
        );
      });
    });

    describe('module installation', function () {
      it('should revert if module has not ERC-6900 module interface', async function () {
        const moduleId = this.randomContract.target; // not a validation module
        const installData = ethers.hexlify(ethers.randomBytes(256));
        const entityId = ethers.hexlify('0x11223344');
        const validationFlags = ethers.hexlify('0x11');
        const validationConfig = ethers.concat([moduleId, entityId, validationFlags]);
        const selectors = [ethers.hexlify('0x11223344')];
        const hooks = [ethers.hexlify(ethers.randomBytes(32))];
        await expect(this.mockFromEntrypoint.installValidation(validationConfig, selectors, installData, hooks))
          .to.be.revertedWithCustomError(this.mock, 'ERC6900ModuleInterfaceNotSupported')
          .withArgs(moduleId, '0x46c0c1b4');
      });

      it('should revert if selector is already set', async function () {
        const moduleId = this.validationModule.target;
        const installData = ethers.hexlify(ethers.randomBytes(256));
        const entityId = ethers.hexlify('0x11223344');
        const validationFlags = ethers.hexlify('0x11');
        const validationConfig = ethers.concat([moduleId, entityId, validationFlags]);
        const selectors = [ethers.hexlify('0x11223344'), ethers.hexlify('0x11223344')]; // same selector twice
        const hooks = [ethers.hexlify(ethers.randomBytes(32))];
        await expect(
          this.mockFromEntrypoint.installValidation(validationConfig, selectors, installData, hooks),
        ).to.be.revertedWithCustomError(this.mock, 'ERC6900AlreadySetSelectorForValidation');
        // .withArgs(moduleId, "0x46c0c1b4");
      });

      it('should revert if validation hook already set', async function () {
        const moduleId = this.validationModule.target;
        const installData = ethers.hexlify(ethers.randomBytes(256));
        const entityId = ethers.hexlify('0x11223344');
        const validationFlags = ethers.hexlify('0x11');
        const validationConfig = ethers.concat([moduleId, entityId, validationFlags]);
        const selectors = [ethers.hexlify('0x11223344')];
        const hook = ethers.concat([ethers.hexlify(ethers.randomBytes(24)), ethers.hexlify('0x01')]);
        const hooks = [hook, hook]; // same validation hook twice
        await expect(
          this.mockFromEntrypoint.installValidation(validationConfig, selectors, installData, hooks),
        ).to.be.revertedWithCustomError(this.mock, 'ERC6900AlreadySetValidationHookForValidation');
      });

      it('should revert if execution hook already set', async function () {
        const moduleId = this.validationModule.target;
        const installData = ethers.hexlify(ethers.randomBytes(256));
        const entityId = ethers.hexlify('0x11223344');
        const validationFlags = ethers.hexlify('0x11');
        const validationConfig = ethers.concat([moduleId, entityId, validationFlags]);
        const selectors = [ethers.hexlify('0x11223344')];
        const hook = ethers.concat([ethers.hexlify(ethers.randomBytes(24)), ethers.hexlify('0x00')]);
        const hooks = [hook, hook]; // same execution hook twice
        await expect(
          this.mockFromEntrypoint.installValidation(validationConfig, selectors, installData, hooks),
        ).to.be.revertedWithCustomError(this.mock, 'ERC6900AlreadySetExecutionHookForValidation');
      });

      it(`should install validation`, async function () {
        const moduleId = this.validationModule.target;
        const installData = ethers.hexlify(ethers.randomBytes(256));
        const entityId = ethers.hexlify('0x11223344');
        const validationFlags = ethers.hexlify('0x11');
        const validationConfig = ethers.concat([moduleId, entityId, validationFlags]);
        const selectors = [ethers.hexlify('0x11223344')];
        const hooks = [ethers.hexlify(ethers.randomBytes(32))];

        await expect(this.mockFromEntrypoint.installValidation(validationConfig, selectors, installData, hooks))
          .to.emit(this.validationModule, 'ModuleInstalledReceived')
          .withArgs(this.mock, installData)
          .to.emit(this.mock, 'ValidationInstalled')
          .withArgs(moduleId, entityId);
      });
    });

    describe('module execution', function () {
      it(`should install execution`, async function () {
        const moduleId = this.executionModule.target;
        const installData = ethers.hexlify(ethers.randomBytes(256));
        const executionSelector = ethers.hexlify('0x11223344');
        const skipRuntimeValidation = true;
        const allowGlobalValidation = true;
        const executionHookSelector = ethers.hexlify('0x11223355');
        const entityId = ethers.hexlify('0x11223366');
        //const executionHookFlags = ethers.hexlify("0x02"); // isPreHook && isPostHook
        const isPreHook = true;
        const isPostHook = true;
        const interfaceId = ethers.hexlify('0x11223377');
        /*
        const executionManifest = ethers.AbiCoder.defaultAbiCoder().encode(
          ['tuple(tuple(bytes4,bool,bool)[],tuple(bytes4,uint32,bool,bool)[],bytes4[])'],
          [
            [
              [[executionSelector, skipRuntimeValidation, allowGlobalValidation]],
              [[executionSelector, entityId, isPreHook, isPostHook]],
              [interfaceId],
            ],
          ],
        );
        */
        await expect(
          this.mockFromEntrypoint.installExecutionFlat(
            moduleId,
            executionSelector,
            executionHookSelector,
            entityId,
            [interfaceId],
            installData,
          ),
        )
          .to.emit(this.executionModule, 'ModuleInstalledReceived')
          .withArgs(this.mock, installData)
          .to.emit(this.mock, 'ExecutionInstalled')
          .withArgs(moduleId, [
            [[executionSelector, skipRuntimeValidation, allowGlobalValidation]],
            [[executionHookSelector, entityId, isPreHook, isPostHook]],
            [interfaceId],
          ]);
      });
    });
  });
}

module.exports = {
  shouldBehaveLikeAccountERC6900,
};
