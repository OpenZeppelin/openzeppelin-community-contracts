const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');
const { selector } = require('@openzeppelin/contracts/test/helpers/methods');
const {
  CALL_TYPE_BATCH,
  encodeMode,
  encodeBatch,
  encodeSingle,
  encodeDelegate,
  EXEC_TYPE_TRY,
  CALL_TYPE_CALL,
  CALL_TYPE_DELEGATE,
  MODULE_TYPE_VALIDATOR,
  MODULE_TYPE_EXECUTOR,
  MODULE_TYPE_FALLBACK,
  MODULE_TYPE_HOOK,
} = require('@openzeppelin/contracts/test/helpers/erc7579');

const CALL_TYPE_INVALID = '0x42';
const MODULE_TYPE_INVALID = 999n;

const coder = ethers.AbiCoder.defaultAbiCoder();

function shouldBehaveLikeAccountERC7579({ withHooks = false } = {}) {
  describe('AccountERC7579', function () {
    beforeEach(async function () {
      await this.mock.deploy();
      await this.other.sendTransaction({ to: this.mock.target, value: ethers.parseEther('1') });
      this.mockFromEntrypoint = this.mock.connect(await impersonate(entrypoint.target));
    });

    describe('accountId', function () {
      it('should return the account ID', async function () {
        await expect(this.mock.accountId()).to.eventually.equal(
          '@openzeppelin/community-contracts.AccountERC7579.v0.0.0',
        );
      });
    });

    describe('supportsExecutionMode', function () {
      it('supports CALL_TYPE_CALL execution mode', async function () {
        await expect(this.mock.supportsExecutionMode(encodeMode({ callType: CALL_TYPE_CALL }))).to.eventually.equal(
          true,
        );
      });

      it('supports CALL_TYPE_BATCH execution mode', async function () {
        await expect(this.mock.supportsExecutionMode(encodeMode({ callType: CALL_TYPE_BATCH }))).to.eventually.equal(
          true,
        );
      });

      it('supports CALL_TYPE_DELEGATE execution mode', async function () {
        await expect(this.mock.supportsExecutionMode(encodeMode({ callType: CALL_TYPE_DELEGATE }))).to.eventually.equal(
          true,
        );
      });

      it('does not supports invalid execution mode', async function () {
        await expect(this.mock.supportsExecutionMode(encodeMode({ callType: CALL_TYPE_INVALID }))).to.eventually.equal(
          false,
        );
      });
    });

    describe('supportsModule', function () {
      it('supports MODULE_TYPE_VALIDATOR module type', async function () {
        await expect(this.mock.supportsModule(MODULE_TYPE_VALIDATOR)).to.eventually.equal(true);
      });

      it('supports MODULE_TYPE_EXECUTOR module type', async function () {
        await expect(this.mock.supportsModule(MODULE_TYPE_EXECUTOR)).to.eventually.equal(true);
      });

      it('supports MODULE_TYPE_FALLBACK module type', async function () {
        await expect(this.mock.supportsModule(MODULE_TYPE_FALLBACK)).to.eventually.equal(true);
      });

      it(
        withHooks ? 'supports MODULE_TYPE_HOOK module type' : 'does not support MODULE_TYPE_HOOK module type',
        async function () {
          await expect(this.mock.supportsModule(MODULE_TYPE_HOOK)).to.eventually.equal(withHooks);
        },
      );

      it('does not support invalid module type', async function () {
        await expect(this.mock.supportsModule(MODULE_TYPE_INVALID)).to.eventually.equal(false);
      });
    });

    describe('module installation', function () {
      it('should revert if the caller is not the canonical entrypoint or the account itself', async function () {
        await expect(this.mock.connect(this.other).installModule(MODULE_TYPE_VALIDATOR, this.mock, '0x'))
          .to.be.revertedWithCustomError(this.mock, 'AccountUnauthorized')
          .withArgs(this.other);
      });

      it('should revert if the module type is not supported', async function () {
        await expect(this.mockFromEntrypoint.installModule(MODULE_TYPE_INVALID, this.mock, '0x'))
          .to.be.revertedWithCustomError(this.mock, 'ERC7579UnsupportedModuleType')
          .withArgs(MODULE_TYPE_INVALID);
      });

      it('should revert if the module is not the provided type', async function () {
        const moduleMock = await ethers.deployContract('$ERC7579ModuleMock', [MODULE_TYPE_EXECUTOR]);

        await expect(this.mockFromEntrypoint.installModule(MODULE_TYPE_VALIDATOR, moduleMock, '0x'))
          .to.be.revertedWithCustomError(this.mock, 'ERC7579MismatchedModuleTypeId')
          .withArgs(MODULE_TYPE_VALIDATOR, moduleMock);
      });

      for (const moduleTypeId of [
        MODULE_TYPE_VALIDATOR,
        MODULE_TYPE_EXECUTOR,
        MODULE_TYPE_FALLBACK,
        withHooks && MODULE_TYPE_HOOK,
      ].filter(Boolean)) {
        it(`should install a module of type ${moduleTypeId}`, async function () {
          const moduleMock = await ethers.deployContract('$ERC7579ModuleMock', [moduleTypeId]);
          const initData = moduleTypeId === MODULE_TYPE_FALLBACK ? '0x12345678abcdef' : '0xabcdef';

          await expect(this.mock.isModuleInstalled(moduleTypeId, moduleMock, initData)).to.eventually.equal(false);

          await expect(this.mockFromEntrypoint.installModule(moduleTypeId, moduleMock, initData))
            .to.emit(this.mock, 'ModuleInstalled')
            .withArgs(moduleTypeId, moduleMock)
            .to.emit(moduleMock, 'ModuleInstalledReceived')
            .withArgs(this.mock, '0xabcdef'); // After decoding MODULE_TYPE_FALLBACK, it should remove the fnSig

          await expect(this.mock.isModuleInstalled(moduleTypeId, moduleMock, initData)).to.eventually.equal(true);
        });

        it(`does not allow to install a module of ${moduleTypeId} id twice`, async function () {
          const moduleMock = await ethers.deployContract('$ERC7579ModuleMock', [moduleTypeId]);
          const initData = moduleTypeId === MODULE_TYPE_FALLBACK ? '0x12345678abcdef' : '0xabcdef';

          await this.mockFromEntrypoint.installModule(moduleTypeId, moduleMock, initData);

          await expect(this.mock.isModuleInstalled(moduleTypeId, moduleMock, initData)).to.eventually.equal(true);

          await expect(this.mockFromEntrypoint.installModule(moduleTypeId, moduleMock, initData))
            .to.be.revertedWithCustomError(this.mock, 'ERC7579AlreadyInstalledModule')
            .withArgs(moduleTypeId, moduleMock);
        });
      }
    });

    describe('module uninstallation', function () {
      it('should revert if the caller is not the canonical entrypoint or the account itself', async function () {
        await expect(this.mock.connect(this.other).uninstallModule(MODULE_TYPE_VALIDATOR, this.mock, '0x'))
          .to.be.revertedWithCustomError(this.mock, 'AccountUnauthorized')
          .withArgs(this.other);
      });

      for (const moduleTypeId of [
        MODULE_TYPE_VALIDATOR,
        MODULE_TYPE_EXECUTOR,
        MODULE_TYPE_FALLBACK,
        withHooks && MODULE_TYPE_HOOK,
      ].filter(Boolean)) {
        it(`should uninstall a module of type ${moduleTypeId}`, async function () {
          const moduleMock = await ethers.deployContract('$ERC7579ModuleMock', [moduleTypeId]);
          const initData = moduleTypeId === MODULE_TYPE_FALLBACK ? '0x12345678abcdef' : '0xabcdef';

          await this.mock.$_installModule(moduleTypeId, moduleMock, initData);

          await expect(this.mock.isModuleInstalled(moduleTypeId, moduleMock, initData)).to.eventually.equal(true);

          await expect(this.mockFromEntrypoint.uninstallModule(moduleTypeId, moduleMock, initData))
            .to.emit(this.mock, 'ModuleUninstalled')
            .withArgs(moduleTypeId, moduleMock)
            .to.emit(moduleMock, 'ModuleUninstalledReceived')
            .withArgs(this.mock, '0xabcdef'); // After decoding MODULE_TYPE_FALLBACK, it should remove the fnSig

          await expect(this.mock.isModuleInstalled(moduleTypeId, moduleMock, initData)).to.eventually.equal(false);
        });

        it(`should revert uninstalling a module of type ${moduleTypeId} if it was not installed`, async function () {
          const moduleMock = await ethers.deployContract('$ERC7579ModuleMock', [moduleTypeId]);
          const initData = moduleTypeId === MODULE_TYPE_FALLBACK ? '0x12345678abcdef' : '0xabcdef';

          await expect(this.mockFromEntrypoint.uninstallModule(moduleTypeId, moduleMock, initData))
            .to.be.revertedWithCustomError(this.mock, 'ERC7579UninstalledModule')
            .withArgs(moduleTypeId, moduleMock);
        });
      }

      it('should revert uninstalling a module of type MODULE_TYPE_FALLBACK if a different module was installed for the provided selector', async function () {
        const moduleMock = await ethers.deployContract('$ERC7579ModuleMock', [MODULE_TYPE_FALLBACK]);
        const anotherModuleMock = await ethers.deployContract('$ERC7579ModuleMock', [MODULE_TYPE_FALLBACK]);
        const initData = '0x12345678abcdef';

        await this.mockFromEntrypoint.$_installModule(MODULE_TYPE_FALLBACK, moduleMock, initData);
        await expect(this.mockFromEntrypoint.uninstallModule(MODULE_TYPE_FALLBACK, anotherModuleMock, initData))
          .to.be.revertedWithCustomError(this.mock, 'ERC7579UninstalledModule')
          .withArgs(MODULE_TYPE_FALLBACK, anotherModuleMock);
      });
    });

    describe('execution', function () {
      beforeEach(async function () {
        this.executorModule = await ethers.deployContract('$ERC7579ModuleMock', [MODULE_TYPE_EXECUTOR]);
        await this.mock.$_installModule(MODULE_TYPE_EXECUTOR, this.executorModule, '0x');
        this.mockFromExecutor = this.mock.connect(await impersonate(this.executorModule.target));
      });

      for (const [execFn, mock] of [
        ['execute', 'mockFromEntrypoint'],
        ['executeFromExecutor', 'mockFromExecutor'],
      ]) {
        describe(`executing with ${execFn}`, function () {
          it('should revert if the call type is not supported', async function () {
            await expect(
              this[mock][execFn](encodeMode({ callType: CALL_TYPE_INVALID }), encodeSingle(this.other, 0, '0x')),
            )
              .to.be.revertedWithCustomError(this.mock, 'ERC7579UnsupportedCallType')
              .withArgs(ethers.solidityPacked(['bytes1'], [CALL_TYPE_INVALID]));
          });

          it('should revert if the caller is not authorized / installed', async function () {
            const error = execFn == 'execute' ? 'AccountUnauthorized' : 'ERC7579UninstalledModule';
            const args = execFn == 'execute' ? [this.other] : [MODULE_TYPE_EXECUTOR, this.other];

            await expect(
              this[mock]
                .connect(this.other)
                [execFn](encodeMode({ callType: CALL_TYPE_CALL }), encodeSingle(this.other, 0, '0x')),
            )
              .to.be.revertedWithCustomError(this.mock, error)
              .withArgs(...args);
          });

          describe('single execution', function () {
            it('calls the target with value and args', async function () {
              const value = 0x432;
              const data = encodeSingle(
                this.target,
                value,
                this.target.interface.encodeFunctionData('mockFunctionWithArgs', [42, '0x1234']),
              );

              const tx = this[mock][execFn](encodeMode({ callType: CALL_TYPE_CALL }), data);

              await expect(tx).to.emit(this.target, 'MockFunctionCalledWithArgs').withArgs(42, '0x1234');
              await expect(tx).to.changeEtherBalances([this.mock, this.target], [-value, value]);
            });

            it('reverts when target reverts in default ExecType', async function () {
              const value = 0x012;
              const data = encodeSingle(
                this.target,
                value,
                this.target.interface.encodeFunctionData('mockFunctionRevertsReason'),
              );

              await expect(this[mock][execFn](encodeMode({ callType: CALL_TYPE_CALL }), data)).to.be.revertedWith(
                'CallReceiverMock: reverting',
              );
            });

            it('emits ERC7579TryExecuteFail event when target reverts in try ExecType', async function () {
              const value = 0x012;
              const data = encodeSingle(
                this.target,
                value,
                this.target.interface.encodeFunctionData('mockFunctionRevertsReason'),
              );

              await expect(this[mock][execFn](encodeMode({ callType: CALL_TYPE_CALL, execType: EXEC_TYPE_TRY }), data))
                .to.emit(this.mock, 'ERC7579TryExecuteFail')
                .withArgs(
                  CALL_TYPE_CALL,
                  ethers.solidityPacked(
                    ['bytes4', 'bytes'],
                    [selector('Error(string)'), coder.encode(['string'], ['CallReceiverMock: reverting'])],
                  ),
                );
            });
          });

          describe('batch execution', function () {
            it('calls the targets with value and args', async function () {
              const value1 = 0x012;
              const value2 = 0x234;
              const data = encodeBatch(
                [this.target, value1, this.target.interface.encodeFunctionData('mockFunctionWithArgs', [42, '0x1234'])],
                [
                  this.anotherTarget,
                  value2,
                  this.anotherTarget.interface.encodeFunctionData('mockFunctionWithArgs', [42, '0x1234']),
                ],
              );

              const tx = this[mock][execFn](encodeMode({ callType: CALL_TYPE_BATCH }), data);
              await expect(tx)
                .to.emit(this.target, 'MockFunctionCalledWithArgs')
                .to.emit(this.anotherTarget, 'MockFunctionCalledWithArgs');
              await expect(tx).to.changeEtherBalances(
                [this.mock, this.target, this.anotherTarget],
                [-value1 - value2, value1, value2],
              );
            });

            it('reverts when any target reverts in default ExecType', async function () {
              const value1 = 0x012;
              const value2 = 0x234;
              const data = encodeBatch(
                [this.target, value1, this.target.interface.encodeFunctionData('mockFunction')],
                [
                  this.anotherTarget,
                  value2,
                  this.anotherTarget.interface.encodeFunctionData('mockFunctionRevertsReason'),
                ],
              );

              await expect(this[mock][execFn](encodeMode({ callType: CALL_TYPE_BATCH }), data)).to.be.revertedWith(
                'CallReceiverMock: reverting',
              );
            });

            it('emits ERC7579TryExecuteFail event when any target reverts in try ExecType', async function () {
              const value1 = 0x012;
              const value2 = 0x234;
              const data = encodeBatch(
                [this.target, value1, this.target.interface.encodeFunctionData('mockFunction')],
                [
                  this.anotherTarget,
                  value2,
                  this.anotherTarget.interface.encodeFunctionData('mockFunctionRevertsReason'),
                ],
              );

              const tx = this[mock][execFn](encodeMode({ callType: CALL_TYPE_BATCH, execType: EXEC_TYPE_TRY }), data);

              await expect(tx)
                .to.emit(this.mock, 'ERC7579TryExecuteFail')
                .withArgs(
                  CALL_TYPE_BATCH,
                  ethers.solidityPacked(
                    ['bytes4', 'bytes'],
                    [selector('Error(string)'), coder.encode(['string'], ['CallReceiverMock: reverting'])],
                  ),
                );

              await expect(tx).to.changeEtherBalances(
                [this.mock, this.target, this.anotherTarget],
                [-value1, value1, 0],
              );
            });
          });

          describe('delegate call execution', function () {
            it('delegate calls the target', async function () {
              const slot = ethers.hexlify(ethers.randomBytes(32));
              const value = ethers.hexlify(ethers.randomBytes(32));
              const data = encodeDelegate(
                this.target,
                this.target.interface.encodeFunctionData('mockFunctionWritesStorage', [slot, value]),
              );

              await expect(ethers.provider.getStorage(this.mock.target, slot)).to.eventually.equal(ethers.ZeroHash);
              await this[mock][execFn](encodeMode({ callType: CALL_TYPE_DELEGATE }), data);
              await expect(ethers.provider.getStorage(this.mock.target, slot)).to.eventually.equal(value);
            });

            it('reverts when target reverts in default ExecType', async function () {
              const data = encodeDelegate(
                this.target,
                this.target.interface.encodeFunctionData('mockFunctionRevertsReason'),
              );
              await expect(this[mock][execFn](encodeMode({ callType: CALL_TYPE_DELEGATE }), data)).to.be.revertedWith(
                'CallReceiverMock: reverting',
              );
            });

            it('emits ERC7579TryExecuteFail event when target reverts in try ExecType', async function () {
              const data = encodeDelegate(
                this.target,
                this.target.interface.encodeFunctionData('mockFunctionRevertsReason'),
              );
              await expect(
                this[mock][execFn](encodeMode({ callType: CALL_TYPE_DELEGATE, execType: EXEC_TYPE_TRY }), data),
              )
                .to.emit(this.mock, 'ERC7579TryExecuteFail')
                .withArgs(
                  CALL_TYPE_CALL,
                  ethers.solidityPacked(
                    ['bytes4', 'bytes'],
                    [selector('Error(string)'), coder.encode(['string'], ['CallReceiverMock: reverting'])],
                  ),
                );
            });
          });

          withHooks &&
            describe('with hook', function () {
              beforeEach(async function () {
                this.hookModule = await ethers.deployContract('$ERC7579HookMock');
                await this.mockFromEntrypoint.$_installModule(MODULE_TYPE_HOOK, this.hookModule, '0x');
              });

              it(`should call the hook of the installed module when executing ${execFn}`, async function () {
                const caller = execFn === 'execute' ? entrypoint : this.executorModule;
                const value = 17;
                const data = this.target.interface.encodeFunctionData('mockFunctionWithArgs', [42, '0x1234']);

                const mode = encodeMode({ callType: CALL_TYPE_CALL });
                const call = encodeSingle(this.target, value, data);
                const precheckData = this[mock].interface.encodeFunctionData(execFn, [mode, call]);

                const tx = this[mock][execFn](mode, call, { value });

                await expect(tx)
                  .to.emit(this.hookModule, 'PreCheck')
                  .withArgs(caller, value, precheckData)
                  .to.emit(this.hookModule, 'PostCheck')
                  .withArgs(precheckData);
                await expect(tx).to.changeEtherBalances([caller, this.mock, this.target], [-value, 0n, value]);
              });
            });
        });
      }
    });

    describe('fallback', function () {
      beforeEach(async function () {
        this.fallbackHandler = await ethers.deployContract('$ERC7579FallbackHandlerMock');
      });

      it('reverts if there is no fallback module installed', async function () {
        const { selector } = this.fallbackHandler.callPayable.getFragment();

        await expect(this.fallbackHandler.attach(this.mock).callPayable())
          .to.be.revertedWithCustomError(this.mock, 'ERC7579MissingFallbackHandler')
          .withArgs(selector);
      });

      describe('with a fallback module installed', function () {
        beforeEach(async function () {
          await Promise.all(
            [
              this.fallbackHandler.callPayable.getFragment().selector,
              this.fallbackHandler.callView.getFragment().selector,
              this.fallbackHandler.callRevert.getFragment().selector,
            ].map(selector =>
              this.mock.$_installModule(
                MODULE_TYPE_FALLBACK,
                this.fallbackHandler,
                coder.encode(['bytes4', 'bytes'], [selector, '0x']),
              ),
            ),
          );
        });

        it('forwards the call to the fallback handler', async function () {
          const calldata = this.fallbackHandler.interface.encodeFunctionData('callPayable');
          const value = 17n;

          await expect(this.fallbackHandler.attach(this.mock).connect(this.other).callPayable({ value }))
            .to.emit(this.fallbackHandler, 'ERC7579FallbackHandlerMockCalled')
            .withArgs(this.mock, this.other, value, calldata);
        });

        it('returns answer from the fallback handler', async function () {
          await expect(this.fallbackHandler.attach(this.mock).connect(this.other).callView()).to.eventually.deep.equal([
            this.mock.target,
            this.other.address,
          ]);
        });

        it('bubble up reverts from the fallback handler', async function () {
          await expect(
            this.fallbackHandler.attach(this.mock).connect(this.other).callRevert(),
          ).to.be.revertedWithCustomError(this.fallbackHandler, 'ERC7579FallbackHandlerMockRevert');
        });

        withHooks &&
          describe('with hook', function () {
            beforeEach(async function () {
              this.hookModule = await ethers.deployContract('$ERC7579HookMock');
              await this.mockFromEntrypoint.$_installModule(MODULE_TYPE_HOOK, this.hookModule, '0x');
            });

            it('should call the hook of the installed module when performing a callback', async function () {
              const precheckData = this.fallbackHandler.interface.encodeFunctionData('callPayable');
              const value = 17n;

              // call with interface: decode returned data
              await expect(this.fallbackHandler.attach(this.mock).connect(this.other).callPayable({ value }))
                .to.emit(this.hookModule, 'PreCheck')
                .withArgs(this.other, value, precheckData)
                .to.emit(this.hookModule, 'PostCheck')
                .withArgs(precheckData);
            });
          });
      });
    });
  });
}

module.exports = {
  shouldBehaveLikeAccountERC7579,
};
