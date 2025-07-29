const { ethers, predeploy } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');
const { ERC4337Helper } = require('@openzeppelin/contracts/test/helpers/erc4337');

const {
  MODULE_TYPE_EXECUTOR,
  encodeSingle,
  encodeMode,
  CALL_TYPE_CALL,
  EXEC_TYPE_DEFAULT,
} = require('@openzeppelin/contracts/test/helpers/erc7579');
const { shouldBehaveLikeERC7579Module } = require('./ERC7579Module.behavior');

async function fixture() {
  // Deploy ERC-7579 selector executor module
  const mock = await ethers.deployContract('$ERC7579SelectorExecutor');
  const target = await ethers.deployContract('CallReceiverMock');

  // ERC-4337 env
  const helper = new ERC4337Helper();
  await helper.wait();

  // ERC-7579 account
  const mockAccount = await helper.newAccount('$AccountERC7579');
  const mockFromAccount = await impersonate(mockAccount.address).then(asAccount => mock.connect(asAccount));
  const mockAccountFromEntrypoint = await impersonate(predeploy.entrypoint.v08.target).then(asEntrypoint =>
    mockAccount.connect(asEntrypoint),
  );

  const moduleType = MODULE_TYPE_EXECUTOR;

  await mockAccount.deploy();

  // Prepare test data
  const args = [42, '0x1234'];
  const data = target.interface.encodeFunctionData('mockFunctionWithArgs', args);
  const calldata = encodeSingle(target, 0, data);
  const mode = encodeMode({ callType: CALL_TYPE_CALL, execType: EXEC_TYPE_DEFAULT });
  const selector = target.interface.getFunction('mockFunctionWithArgs').selector;

  // Additional selectors for testing
  const mockFunctionSelector = target.interface.getFunction('mockFunction').selector;
  const mockFunctionExtraSelector = target.interface.getFunction('mockFunctionExtra').selector;

  return {
    moduleType,
    mock,
    mockAccount,
    mockFromAccount,
    mockAccountFromEntrypoint,
    target,
    args,
    data,
    calldata,
    mode,
    selector,
    mockFunctionSelector,
    mockFunctionExtraSelector,
  };
}

describe('ERC7579SelectorExecutor', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeERC7579Module();

  describe('installation and setup', function () {
    it('installs with empty data', async function () {
      await this.mockAccountFromEntrypoint.installModule(this.moduleType, this.mock.target, '0x');

      // Should have no authorized selectors initially
      await expect(this.mock.selectors(this.mockAccount.address)).to.eventually.deep.equal([]);
    });

    it('installs with initial selectors', async function () {
      const initialSelectors = [this.selector, this.mockFunctionSelector];
      const installData = ethers.AbiCoder.defaultAbiCoder().encode(['bytes4[]'], [initialSelectors]);

      await expect(this.mockAccountFromEntrypoint.installModule(this.moduleType, this.mock.target, installData))
        .to.emit(this.mock, 'ERC7579ExecutorSelectorAuthorized')
        .withArgs(this.mockAccount.address, this.selector)
        .to.emit(this.mock, 'ERC7579ExecutorSelectorAuthorized')
        .withArgs(this.mockAccount.address, this.mockFunctionSelector);

      // Should have the initial selectors
      const authorizedSelectors = await this.mock.selectors(this.mockAccount.address);
      expect(authorizedSelectors).to.have.lengthOf(2);
      expect(authorizedSelectors).to.include(this.selector);
      expect(authorizedSelectors).to.include(this.mockFunctionSelector);
    });

    it('cleans up selectors on uninstall', async function () {
      const initialSelectors = [this.selector, this.mockFunctionSelector];
      const installData = ethers.AbiCoder.defaultAbiCoder().encode(['bytes4[]'], [initialSelectors]);

      await this.mockAccountFromEntrypoint.installModule(this.moduleType, this.mock.target, installData);

      // Verify selectors are installed
      await expect(this.mock.selectors(this.mockAccount.address)).to.eventually.have.lengthOf(2);

      // Uninstall and verify cleanup
      await this.mockAccountFromEntrypoint.uninstallModule(this.moduleType, this.mock.target, '0x');
      await expect(this.mock.selectors(this.mockAccount.address)).to.eventually.deep.equal([]);
    });
  });

  describe('selector management', function () {
    beforeEach(async function () {
      await this.mockAccountFromEntrypoint.installModule(this.moduleType, this.mock.target, '0x');
    });

    it('adds selectors', async function () {
      const selectorsToAdd = [this.selector, this.mockFunctionSelector];

      await expect(this.mockFromAccount.addSelectors(selectorsToAdd))
        .to.emit(this.mock, 'ERC7579ExecutorSelectorAuthorized')
        .withArgs(this.mockAccount.address, this.selector)
        .to.emit(this.mock, 'ERC7579ExecutorSelectorAuthorized')
        .withArgs(this.mockAccount.address, this.mockFunctionSelector);

      // Verify selectors are added
      const authorizedSelectors = await this.mock.selectors(this.mockAccount.address);
      expect(authorizedSelectors).to.have.lengthOf(2);
      expect(authorizedSelectors).to.include(this.selector);
      expect(authorizedSelectors).to.include(this.mockFunctionSelector);

      // Verify isAuthorized function
      await expect(this.mock.isAuthorized(this.mockAccount.address, this.selector)).to.eventually.be.true;
      await expect(this.mock.isAuthorized(this.mockAccount.address, this.mockFunctionSelector)).to.eventually.be.true;
      await expect(this.mock.isAuthorized(this.mockAccount.address, this.mockFunctionExtraSelector)).to.eventually.be
        .false;
    });

    it('removes selectors', async function () {
      // First add some selectors
      const selectorsToAdd = [this.selector, this.mockFunctionSelector, this.mockFunctionExtraSelector];
      await this.mockFromAccount.addSelectors(selectorsToAdd);

      // Remove some selectors
      const selectorsToRemove = [this.mockFunctionSelector];
      await expect(this.mockFromAccount.removeSelectors(selectorsToRemove))
        .to.emit(this.mock, 'ERC7579ExecutorSelectorRemoved')
        .withArgs(this.mockAccount.address, this.mockFunctionSelector);

      // Verify selectors are removed
      const authorizedSelectors = await this.mock.selectors(this.mockAccount.address);
      expect(authorizedSelectors).to.have.lengthOf(2);
      expect(authorizedSelectors).to.include(this.selector);
      expect(authorizedSelectors).to.include(this.mockFunctionExtraSelector);
      expect(authorizedSelectors).to.not.include(this.mockFunctionSelector);

      // Verify isAuthorized function
      await expect(this.mock.isAuthorized(this.mockAccount.address, this.selector)).to.eventually.be.true;
      await expect(this.mock.isAuthorized(this.mockAccount.address, this.mockFunctionSelector)).to.eventually.be.false;
      await expect(this.mock.isAuthorized(this.mockAccount.address, this.mockFunctionExtraSelector)).to.eventually.be
        .true;
    });

    it('handles duplicate additions gracefully', async function () {
      // Add selector twice
      await this.mockFromAccount.addSelectors([this.selector]);

      // Adding again should be a no-op (no event emitted)
      await expect(this.mockFromAccount.addSelectors([this.selector])).to.not.emit(
        this.mock,
        'ERC7579ExecutorSelectorAuthorized',
      );

      // Should still have only one instance
      const authorizedSelectors = await this.mock.selectors(this.mockAccount.address);
      expect(authorizedSelectors).to.have.lengthOf(1);
      expect(authorizedSelectors[0]).to.equal(this.selector);
    });

    it('handles removal of non-existent selectors gracefully', async function () {
      // Try to remove a selector that wasn't added
      await expect(this.mockFromAccount.removeSelectors([this.selector])).to.not.emit(
        this.mock,
        'ERC7579ExecutorSelectorRemoved',
      );

      // Should still have no selectors
      await expect(this.mock.selectors(this.mockAccount.address)).to.eventually.deep.equal([]);
    });
  });

  describe('execution validation', function () {
    beforeEach(async function () {
      await this.mockAccountFromEntrypoint.installModule(this.moduleType, this.mock.target, '0x');
    });

    it('allows execution of authorized selectors', async function () {
      // Authorize the selector
      await this.mockFromAccount.addSelectors([this.selector]);

      // Should succeed
      await expect(this.mockFromAccount.execute(this.mockAccount.address, ethers.ZeroHash, this.mode, this.calldata))
        .to.emit(this.mock, 'ERC7579ExecutorOperationExecuted')
        .to.emit(this.target, 'MockFunctionCalledWithArgs')
        .withArgs(...this.args);
    });

    it('rejects execution of unauthorized selectors', async function () {
      // Don't authorize the selector, try to execute
      await expect(this.mockFromAccount.execute(this.mockAccount.address, ethers.ZeroHash, this.mode, this.calldata))
        .to.be.revertedWithCustomError(this.mock, 'ERC7579ExecutorSelectorNotAuthorized')
        .withArgs(this.selector);
    });

    it('allows execution after adding selector', async function () {
      // First execution should fail
      await expect(this.mockFromAccount.execute(this.mockAccount.address, ethers.ZeroHash, this.mode, this.calldata))
        .to.be.revertedWithCustomError(this.mock, 'ERC7579ExecutorSelectorNotAuthorized')
        .withArgs(this.selector);

      // Add selector
      await this.mockFromAccount.addSelectors([this.selector]);

      // Now execution should succeed
      await expect(this.mockFromAccount.execute(this.mockAccount.address, ethers.ZeroHash, this.mode, this.calldata))
        .to.emit(this.mock, 'ERC7579ExecutorOperationExecuted')
        .to.emit(this.target, 'MockFunctionCalledWithArgs')
        .withArgs(...this.args);
    });

    it('rejects execution after removing selector', async function () {
      // Add and authorize selector first
      await this.mockFromAccount.addSelectors([this.selector]);

      // Execution should succeed
      await expect(
        this.mockFromAccount.execute(this.mockAccount.address, ethers.ZeroHash, this.mode, this.calldata),
      ).to.emit(this.mock, 'ERC7579ExecutorOperationExecuted');

      // Remove selector
      await this.mockFromAccount.removeSelectors([this.selector]);

      // Now execution should fail
      await expect(this.mockFromAccount.execute(this.mockAccount.address, ethers.ZeroHash, this.mode, this.calldata))
        .to.be.revertedWithCustomError(this.mock, 'ERC7579ExecutorSelectorNotAuthorized')
        .withArgs(this.selector);
    });
  });

  describe('edge cases', function () {
    beforeEach(async function () {
      await this.mockAccountFromEntrypoint.installModule(this.moduleType, this.mock.target, '0x');
    });

    it('handles empty selector arrays', async function () {
      // Adding empty array should be no-op
      await this.mockFromAccount.addSelectors([]);
      await expect(this.mock.selectors(this.mockAccount.address)).to.eventually.deep.equal([]);

      // Removing empty array should be no-op
      await this.mockFromAccount.removeSelectors([]);
      await expect(this.mock.selectors(this.mockAccount.address)).to.eventually.deep.equal([]);
    });

    it('handles multiple selector operations', async function () {
      const allSelectors = [this.selector, this.mockFunctionSelector, this.mockFunctionExtraSelector];

      // Add all selectors at once
      await this.mockFromAccount.addSelectors(allSelectors);
      await expect(this.mock.selectors(this.mockAccount.address)).to.eventually.have.lengthOf(3);

      // Remove all selectors at once
      await this.mockFromAccount.removeSelectors(allSelectors);
      await expect(this.mock.selectors(this.mockAccount.address)).to.eventually.deep.equal([]);
    });

    it('validates different function calls correctly', async function () {
      // Authorize only one specific function
      await this.mockFromAccount.addSelectors([this.mockFunctionSelector]);

      // Call to authorized function should work
      const authorizedData = this.target.interface.encodeFunctionData('mockFunction');
      const authorizedCalldata = encodeSingle(this.target, 0, authorizedData);

      await expect(
        this.mockFromAccount.execute(this.mockAccount.address, ethers.ZeroHash, this.mode, authorizedCalldata),
      )
        .to.emit(this.mock, 'ERC7579ExecutorOperationExecuted')
        .to.emit(this.target, 'MockFunctionCalled');

      // Call to unauthorized function should fail
      const unauthorizedData = this.target.interface.encodeFunctionData('mockFunctionExtra');
      const unauthorizedCalldata = encodeSingle(this.target, 0, unauthorizedData);

      await expect(
        this.mockFromAccount.execute(this.mockAccount.address, ethers.ZeroHash, this.mode, unauthorizedCalldata),
      )
        .to.be.revertedWithCustomError(this.mock, 'ERC7579ExecutorSelectorNotAuthorized')
        .withArgs(this.mockFunctionExtraSelector);
    });

    it('handles malformed calldata gracefully', async function () {
      // Try to execute with calldata too short to extract selector
      const shortCalldata = '0x1234'; // Only 2 bytes, need 4 for selector

      // This should revert when trying to extract the selector, but behavior depends on how account handles it
      // The test verifies that our module doesn't crash with malformed data
      await expect(this.mockFromAccount.execute(this.mockAccount.address, ethers.ZeroHash, this.mode, shortCalldata)).to
        .be.reverted; // Could be various revert reasons depending on account implementation
    });
  });

  describe('integration tests', function () {
    it('works with installation, management, and execution flow', async function () {
      // Install with initial selectors
      const initialSelectors = [this.mockFunctionSelector];
      const installData = ethers.AbiCoder.defaultAbiCoder().encode(['bytes4[]'], [initialSelectors]);
      await this.mockAccountFromEntrypoint.installModule(this.moduleType, this.mock.target, installData);

      // Execute authorized function
      const authorizedData = this.target.interface.encodeFunctionData('mockFunction');
      const authorizedCalldata = encodeSingle(this.target, 0, authorizedData);
      await expect(
        this.mockFromAccount.execute(this.mockAccount.address, ethers.ZeroHash, this.mode, authorizedCalldata),
      ).to.emit(this.target, 'MockFunctionCalled');

      // Add more selectors
      await this.mockFromAccount.addSelectors([this.selector]);

      // Execute newly authorized function
      await expect(this.mockFromAccount.execute(this.mockAccount.address, ethers.ZeroHash, this.mode, this.calldata))
        .to.emit(this.target, 'MockFunctionCalledWithArgs')
        .withArgs(...this.args);

      // Remove one selector
      await this.mockFromAccount.removeSelectors([this.mockFunctionSelector]);

      // Previously authorized function should now fail
      await expect(
        this.mockFromAccount.execute(this.mockAccount.address, ethers.ZeroHash, this.mode, authorizedCalldata),
      )
        .to.be.revertedWithCustomError(this.mock, 'ERC7579ExecutorSelectorNotAuthorized')
        .withArgs(this.mockFunctionSelector);

      // But the other function should still work
      await expect(this.mockFromAccount.execute(this.mockAccount.address, ethers.ZeroHash, this.mode, this.calldata))
        .to.emit(this.target, 'MockFunctionCalledWithArgs')
        .withArgs(...this.args);
    });
  });
});
