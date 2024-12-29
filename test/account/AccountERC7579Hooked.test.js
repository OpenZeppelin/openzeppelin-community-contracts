const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const {
  MODULE_TYPE_HOOK,
  encodeSingle,
  encodeMode,
  CALL_TYPE_CALL,
  MODULE_TYPE_EXECUTOR,
} = require('@openzeppelin/contracts/test/helpers/erc7579');
const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');
const { ERC4337Helper } = require('../helpers/erc4337');
const { NonNativeSigner } = require('../helpers/signers');
const { PackedUserOperation } = require('../helpers/eip712-types');

const { shouldBehaveLikeAccountCore, shouldBehaveLikeAccountERC7579 } = require('./Account.behavior');

async function fixture() {
  // EOAs and environment
  const [other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');
  const anotherTarget = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-7579 validator
  const validatorMock = await ethers.deployContract('$ERC7579ValidatorMock');

  // ERC-4337 signer
  const signer = new NonNativeSigner({ sign: () => ({ serialized: '0x01' }) });

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const mock = await helper.newAccount('$AccountERC7579HookedMock', [
    'AccountERC7579Hooked',
    '1',
    validatorMock.target,
    '0x',
  ]);

  // domain cannot be fetched using getDomain(mock) before the mock is deployed
  const domain = {
    name: 'AccountERC7579Hooked',
    version: '1',
    chainId: env.chainId,
    verifyingContract: mock.address,
  };

  const signUserOp = userOp =>
    signer
      .signTypedData(domain, { PackedUserOperation }, userOp.packed)
      .then(signature => Object.assign(userOp, { signature }));

  const userOp = {
    // Use the first 20 bytes from the nonce key (24 bytes) to identify the validator module
    nonce: ethers.zeroPadBytes(ethers.hexlify(validatorMock.target), 32),
  };

  return { ...env, mock, domain, signer, target, anotherTarget, other, signUserOp, userOp };
}

describe('AccountERC7579Hooked', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeAccountCore();
  shouldBehaveLikeAccountERC7579();

  describe('hook', function () {
    beforeEach(async function () {
      await this.mock.deploy();
      this.mockFromEntrypoint = this.mock.connect(await impersonate(entrypoint.target));
    });

    describe('supportsModule', function () {
      it('supports MODULE_TYPE_VALIDATOR module type', async function () {
        await expect(this.mock.supportsModule(MODULE_TYPE_HOOK)).to.eventually.equal(true);
      });
    });

    it(`should install a module of type ${MODULE_TYPE_HOOK}`, async function () {
      const moduleMock = await ethers.deployContract('$ERC7579HookMock');
      await expect(this.mockFromEntrypoint.installModule(MODULE_TYPE_HOOK, moduleMock, '0x'))
        .to.emit(this.mock, 'ModuleInstalled')
        .withArgs(MODULE_TYPE_HOOK, moduleMock)
        .to.emit(moduleMock, 'ModuleInstalledReceived')
        .withArgs(this.mock, '0x');
      await expect(this.mock.isModuleInstalled(MODULE_TYPE_HOOK, moduleMock, '0x')).to.eventually.equal(true);
      await expect(this.mock.hook()).to.eventually.equal(moduleMock.target);
    });

    it(`should uninstall a module of type ${MODULE_TYPE_HOOK}`, async function () {
      const moduleMock = await ethers.deployContract('$ERC7579HookMock');
      await this.mockFromEntrypoint.installModule(MODULE_TYPE_HOOK, moduleMock, '0x');
      await expect(this.mockFromEntrypoint.uninstallModule(MODULE_TYPE_HOOK, moduleMock, '0x'))
        .to.emit(this.mock, 'ModuleUninstalled')
        .withArgs(MODULE_TYPE_HOOK, moduleMock)
        .to.emit(moduleMock, 'ModuleUninstalledReceived')
        .withArgs(this.mock, '0x');
      await expect(this.mock.isModuleInstalled(MODULE_TYPE_HOOK, moduleMock, '0x')).to.eventually.equal(false);
      await expect(this.mock.hook()).to.eventually.equal(ethers.ZeroAddress);
    });

    describe('execution hooks', function () {
      beforeEach(async function () {
        this.moduleMock = await ethers.deployContract('$ERC7579HookMock');
        await this.mockFromEntrypoint.$_installModule(MODULE_TYPE_HOOK, this.moduleMock, '0x');

        this.executorMock = await ethers.deployContract('$ERC7579ModuleMock', [MODULE_TYPE_EXECUTOR]);
        await this.mockFromEntrypoint.$_installModule(MODULE_TYPE_EXECUTOR, this.executorMock, '0x');
        this.mockFromExecutor = this.mock.connect(await impersonate(this.executorMock.target));
      });

      it(`should call the hook of the installed module when executing through executeUserOp`, async function () {
        const value = 0x00; // Can't use 0x00 as value since `execute` is not payable
        const data = this.target.interface.encodeFunctionData('mockFunctionWithArgs', [42, '0x1234']);
        const opts = { value };

        const mode = encodeMode({ callType: CALL_TYPE_CALL });
        const call = encodeSingle(this.target, value, data);

        const precheckData = this.mockFromEntrypoint.interface.encodeFunctionData('execute', [mode, call]);
        const operation = await this.mock.createUserOp({
          callData: ethers.concat([
            this.mockFromEntrypoint.interface.getFunction('executeUserOp').selector,
            precheckData,
          ]),
        });

        await expect(this.mockFromEntrypoint.executeUserOp(operation.packed, operation.hash(), opts))
          .to.emit(this.moduleMock, 'PreCheck')
          .withArgs(entrypoint, value, precheckData)
          .to.emit(this.moduleMock, 'PostCheck')
          .withArgs(precheckData);

        await expect(ethers.provider.getBalance(this.target)).to.eventually.equal(value);
      });

      for (const [execFn, mock] of [
        ['execute', 'mockFromEntrypoint'],
        ['executeFromExecutor', 'mockFromExecutor'],
      ]) {
        it(`should call the hook of the installed module when executing ${execFn}`, async function () {
          const value = 0x00; // Can't use 0x00 as value since neither `execute` nor `executeFromExecutor` are payable
          const data = this.target.interface.encodeFunctionData('mockFunctionWithArgs', [42, '0x1234']);
          const opts = { value };

          const mode = encodeMode({ callType: CALL_TYPE_CALL });
          const call = encodeSingle(this.target, value, data);

          const precheckData = this[mock].interface.encodeFunctionData(execFn, [mode, call]);

          await expect(this[mock][execFn](mode, call, opts))
            .to.emit(this.moduleMock, 'PreCheck')
            .withArgs(execFn === 'execute' ? entrypoint : this.executorMock, value, precheckData)
            .to.emit(this.moduleMock, 'PostCheck')
            .withArgs(precheckData);

          await expect(ethers.provider.getBalance(this.target)).to.eventually.equal(value);
        });
      }
    });
  });
});
