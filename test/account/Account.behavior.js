const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const { setBalance } = require('@nomicfoundation/hardhat-network-helpers');

const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');
const { SIG_VALIDATION_SUCCESS, SIG_VALIDATION_FAILURE } = require('@openzeppelin/contracts/test/helpers/erc4337');
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
} = require('@openzeppelin/contracts/test/helpers/erc7579');
const {
  shouldSupportInterfaces,
} = require('@openzeppelin/contracts/test/utils/introspection/SupportsInterface.behavior');
const { selector } = require('@openzeppelin/contracts/test/helpers/methods');

const value = ethers.parseEther('0.1');

function shouldBehaveLikeAccountCore() {
  describe('entryPoint', function () {
    it('should return the canonical entrypoint', async function () {
      await this.mock.deploy();
      expect(this.mock.entryPoint()).to.eventually.equal(entrypoint);
    });
  });

  describe('validateUserOp', function () {
    beforeEach(async function () {
      await setBalance(this.mock.target, ethers.parseEther('1'));
      await this.mock.deploy();
    });

    it('should revert if the caller is not the canonical entrypoint', async function () {
      // empty operation (does nothing)
      const operation = await this.mock.createUserOp({}).then(op => this.signUserOp(op));

      await expect(this.mock.connect(this.other).validateUserOp(operation.packed, operation.hash(), 0))
        .to.be.revertedWithCustomError(this.mock, 'AccountUnauthorized')
        .withArgs(this.other);
    });

    describe('when the caller is the canonical entrypoint', function () {
      beforeEach(async function () {
        this.mockFromEntrypoint = this.mock.connect(await impersonate(entrypoint.target));
      });

      it('should return SIG_VALIDATION_SUCCESS if the signature is valid', async function () {
        // empty operation (does nothing)
        const operation = await this.mock.createUserOp({}).then(op => this.signUserOp(op));

        expect(await this.mockFromEntrypoint.validateUserOp.staticCall(operation.packed, operation.hash(), 0)).to.eq(
          SIG_VALIDATION_SUCCESS,
        );
      });

      it('should return SIG_VALIDATION_FAILURE if the signature is invalid', async function () {
        // empty operation (does nothing)
        const operation = await this.mock.createUserOp({});
        operation.signature = '0x00';

        expect(await this.mockFromEntrypoint.validateUserOp.staticCall(operation.packed, operation.hash(), 0)).to.eq(
          SIG_VALIDATION_FAILURE,
        );
      });

      it('should pay missing account funds for execution', async function () {
        // empty operation (does nothing)
        const operation = await this.mock.createUserOp({}).then(op => this.signUserOp(op));

        await expect(
          this.mockFromEntrypoint.validateUserOp(operation.packed, operation.hash(), value),
        ).to.changeEtherBalances([this.mock, entrypoint], [-value, value]);
      });
    });
  });

  describe('fallback', function () {
    it('should receive ether', async function () {
      await this.mock.deploy();

      await expect(this.other.sendTransaction({ to: this.mock, value })).to.changeEtherBalances(
        [this.other, this.mock],
        [-value, value],
      );
    });
  });
}

function shouldBehaveLikeAccountHolder() {
  describe('onReceived', function () {
    beforeEach(async function () {
      await this.mock.deploy();
    });

    shouldSupportInterfaces(['ERC1155Receiver']);

    describe('onERC1155Received', function () {
      const ids = [1n, 2n, 3n];
      const values = [1000n, 2000n, 3000n];
      const data = '0x12345678';

      beforeEach(async function () {
        this.token = await ethers.deployContract('$ERC1155Mock', ['https://somedomain.com/{id}.json']);
        await this.token.$_mintBatch(this.other, ids, values, '0x');
      });

      it('receives ERC1155 tokens from a single ID', async function () {
        await this.token.connect(this.other).safeTransferFrom(this.other, this.mock, ids[0], values[0], data);

        expect(
          this.token.balanceOfBatch(
            ids.map(() => this.mock),
            ids,
          ),
        ).to.eventually.deep.equal(values.map((v, i) => (i == 0 ? v : 0n)));
      });

      it('receives ERC1155 tokens from a multiple IDs', async function () {
        expect(
          this.token.balanceOfBatch(
            ids.map(() => this.mock),
            ids,
          ),
        ).to.eventually.deep.equal(ids.map(() => 0n));

        await this.token.connect(this.other).safeBatchTransferFrom(this.other, this.mock, ids, values, data);
        expect(
          this.token.balanceOfBatch(
            ids.map(() => this.mock),
            ids,
          ),
        ).to.eventually.deep.equal(values);
      });
    });

    describe('onERC721Received', function () {
      const tokenId = 1n;

      beforeEach(async function () {
        this.token = await ethers.deployContract('$ERC721Mock', ['Some NFT', 'SNFT']);
        await this.token.$_mint(this.other, tokenId);
      });

      it('receives an ERC721 token', async function () {
        await this.token.connect(this.other).safeTransferFrom(this.other, this.mock, tokenId);

        expect(this.token.ownerOf(tokenId)).to.eventually.equal(this.mock);
      });
    });
  });
}

function shouldBehaveLikeAccountERC7821({ deployable = true } = {}) {
  describe('execute', function () {
    beforeEach(async function () {
      // give eth to the account (before deployment)
      await setBalance(this.mock.target, ethers.parseEther('1'));

      // account is not initially deployed
      expect(ethers.provider.getCode(this.mock)).to.eventually.equal('0x');

      this.encodeUserOpCalldata = (...calls) =>
        this.mock.interface.encodeFunctionData('execute', [
          encodeMode({ callType: CALL_TYPE_BATCH }),
          encodeBatch(...calls),
        ]);
    });

    it('should revert if the caller is not the canonical entrypoint or the account itself', async function () {
      await this.mock.deploy();

      await expect(
        this.mock.connect(this.other).execute(
          encodeMode({ callType: CALL_TYPE_BATCH }),
          encodeBatch({
            target: this.target,
            data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
          }),
        ),
      )
        .to.be.revertedWithCustomError(this.mock, 'AccountUnauthorized')
        .withArgs(this.other);
    });

    if (deployable) {
      describe('when not deployed', function () {
        it('should be created with handleOps and increase nonce', async function () {
          const operation = await this.mock
            .createUserOp({
              callData: this.encodeUserOpCalldata({
                target: this.target,
                value: 17,
                data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
              }),
            })
            .then(op => op.addInitCode())
            .then(op => this.signUserOp(op));

          expect(this.mock.getNonce()).to.eventually.equal(0);
          await expect(entrypoint.handleOps([operation.packed], this.beneficiary))
            .to.emit(entrypoint, 'AccountDeployed')
            .withArgs(operation.hash(), this.mock, this.factory, ethers.ZeroAddress)
            .to.emit(this.target, 'MockFunctionCalledExtra')
            .withArgs(this.mock, 17);
          expect(this.mock.getNonce()).to.eventually.equal(1);
        });

        it('should revert if the signature is invalid', async function () {
          const operation = await this.mock
            .createUserOp({
              callData: this.encodeUserOpCalldata({
                target: this.target,
                value: 17,
                data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
              }),
            })
            .then(op => op.addInitCode());

          operation.signature = '0x00';

          await expect(entrypoint.handleOps([operation.packed], this.beneficiary)).to.be.reverted;
        });
      });
    }

    describe('when deployed', function () {
      beforeEach(async function () {
        await this.mock.deploy();
      });

      it('should increase nonce and call target', async function () {
        const operation = await this.mock
          .createUserOp({
            callData: this.encodeUserOpCalldata({
              target: this.target,
              value: 42,
              data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
            }),
          })
          .then(op => this.signUserOp(op));

        expect(this.mock.getNonce()).to.eventually.equal(0);
        await expect(entrypoint.handleOps([operation.packed], this.beneficiary))
          .to.emit(this.target, 'MockFunctionCalledExtra')
          .withArgs(this.mock, 42);
        expect(this.mock.getNonce()).to.eventually.equal(1);
      });

      it('should support sending eth to an EOA', async function () {
        const operation = await this.mock
          .createUserOp({ callData: this.encodeUserOpCalldata({ target: this.other, value }) })
          .then(op => this.signUserOp(op));

        expect(this.mock.getNonce()).to.eventually.equal(0);
        await expect(entrypoint.handleOps([operation.packed], this.beneficiary)).to.changeEtherBalance(
          this.other,
          value,
        );
        expect(this.mock.getNonce()).to.eventually.equal(1);
      });

      it('should support batch execution', async function () {
        const value1 = 43374337n;
        const value2 = 69420n;

        const operation = await this.mock
          .createUserOp({
            callData: this.encodeUserOpCalldata(
              { target: this.other, value: value1 },
              {
                target: this.target,
                value: value2,
                data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
              },
            ),
          })
          .then(op => this.signUserOp(op));

        expect(this.mock.getNonce()).to.eventually.equal(0);
        const tx = entrypoint.handleOps([operation.packed], this.beneficiary);
        await expect(tx).to.changeEtherBalances([this.other, this.target], [value1, value2]);
        await expect(tx).to.emit(this.target, 'MockFunctionCalledExtra').withArgs(this.mock, value2);
        expect(this.mock.getNonce()).to.eventually.equal(1);
      });
    });
  });
}

function shouldBehaveLikeAccountERC7579() {
  const fnSig = '0x12345678';
  const coder = ethers.AbiCoder.defaultAbiCoder();
  const data = coder.encode(['bytes4', 'bytes'], [fnSig, '0x']); // Min data for MODULE_TYPE_FALLBACK

  describe('AccountERC7579', function () {
    beforeEach(async function () {
      await this.mock.deploy();
    });

    describe('accountId', function () {
      it('should return the account ID', async function () {
        await expect(this.mock.accountId()).to.eventually.equal('@openzeppelin/contracts.erc7579account.v0-beta');
      });
    });

    describe('supportsExecutionMode', function () {
      it('supports CALL_TYPE_CALL execution mode', async function () {
        await expect(this.mock.supportsExecutionMode(CALL_TYPE_CALL)).to.eventually.equal(true);
      });

      it('supports CALL_TYPE_BATCH execution mode', async function () {
        await expect(this.mock.supportsExecutionMode(CALL_TYPE_BATCH)).to.eventually.equal(true);
      });

      it('supports CALL_TYPE_DELEGATE execution mode', async function () {
        await expect(this.mock.supportsExecutionMode(CALL_TYPE_DELEGATE)).to.eventually.equal(true);
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
    });

    describe('module installation', function () {
      beforeEach(async function () {
        this.mockFromEntrypoint = this.mock.connect(await impersonate(entrypoint.target));
      });

      it('should revert if the caller is not the canonical entrypoint or the account itself', async function () {
        await expect(this.mock.connect(this.other).installModule(MODULE_TYPE_VALIDATOR, this.mock, '0x'))
          .to.be.revertedWithCustomError(this.mock, 'AccountUnauthorized')
          .withArgs(this.other);
      });

      it('should revert if the module type is not supported', async function () {
        await expect(this.mockFromEntrypoint.installModule(999, this.mock, '0x'))
          .to.be.revertedWithCustomError(this.mock, 'ERC7579UnsupportedModuleType')
          .withArgs(999);
      });

      it('should revert if the module is not the provided type', async function () {
        const moduleMock = await ethers.deployContract('$ERC7579ModuleMock', [MODULE_TYPE_EXECUTOR]);
        await expect(this.mockFromEntrypoint.installModule(MODULE_TYPE_VALIDATOR, moduleMock, '0x'))
          .to.be.revertedWithCustomError(this.mock, 'ERC7579MismatchedModuleTypeId')
          .withArgs(MODULE_TYPE_VALIDATOR, moduleMock);
      });

      for (const moduleTypeId of [MODULE_TYPE_VALIDATOR, MODULE_TYPE_EXECUTOR]) {
        it(`does not allow to install a module of ${moduleTypeId} id twice`, async function () {
          const moduleMock = await ethers.deployContract('$ERC7579ModuleMock', [moduleTypeId]);
          const initData = moduleTypeId === MODULE_TYPE_FALLBACK ? data : '0x';
          await this.mockFromEntrypoint.installModule(moduleTypeId, moduleMock, initData);
          await expect(this.mockFromEntrypoint.installModule(moduleTypeId, moduleMock, initData))
            .to.be.revertedWithCustomError(this.mock, 'ERC7579AlreadyInstalledModule')
            .withArgs(moduleTypeId, moduleMock);
        });
      }

      for (const moduleTypeId of [MODULE_TYPE_VALIDATOR, MODULE_TYPE_EXECUTOR, MODULE_TYPE_FALLBACK]) {
        it(`should install a module of type ${moduleTypeId}`, async function () {
          const moduleMock = await ethers.deployContract('$ERC7579ModuleMock', [moduleTypeId]);
          const initData = moduleTypeId === MODULE_TYPE_FALLBACK ? data : '0x';
          await expect(this.mockFromEntrypoint.installModule(moduleTypeId, moduleMock, initData))
            .to.emit(this.mock, 'ModuleInstalled')
            .withArgs(moduleTypeId, moduleMock)
            .to.emit(moduleMock, 'ModuleInstalledReceived')
            .withArgs(this.mock, '0x'); // After decoding MODULE_TYPE_FALLBACK, it should remove the fnSig
          await expect(this.mock.isModuleInstalled(moduleTypeId, moduleMock, initData)).to.eventually.equal(true);
        });
      }
    });

    describe('module uninstallation', function () {
      beforeEach(async function () {
        this.mockFromEntrypoint = this.mock.connect(await impersonate(entrypoint.target));
      });

      it('should revert if the caller is not the canonical entrypoint or the account itself', async function () {
        await expect(this.mock.connect(this.other).uninstallModule(MODULE_TYPE_VALIDATOR, this.mock, '0x'))
          .to.be.revertedWithCustomError(this.mock, 'AccountUnauthorized')
          .withArgs(this.other);
      });

      for (const moduleTypeId of [MODULE_TYPE_VALIDATOR, MODULE_TYPE_EXECUTOR, MODULE_TYPE_FALLBACK]) {
        it(`should revert uninstalling a module of type ${moduleTypeId} if it was not installed`, async function () {
          const moduleMock = await ethers.deployContract('$ERC7579ModuleMock', [moduleTypeId]);
          await expect(
            this.mockFromEntrypoint.uninstallModule(
              moduleTypeId,
              moduleMock,
              moduleTypeId === MODULE_TYPE_FALLBACK ? data : '0x',
            ),
          )
            .to.be.revertedWithCustomError(this.mock, 'ERC7579UninstalledModule')
            .withArgs(moduleTypeId, moduleMock);
        });
      }

      for (const moduleTypeId of [MODULE_TYPE_VALIDATOR, MODULE_TYPE_EXECUTOR, MODULE_TYPE_FALLBACK]) {
        it(`should uninstall a module of type ${moduleTypeId}`, async function () {
          const moduleMock = await ethers.deployContract('$ERC7579ModuleMock', [moduleTypeId]);
          const deinitData = moduleTypeId === MODULE_TYPE_FALLBACK ? data : '0x';
          await this.mock.$_installModule(moduleTypeId, moduleMock, deinitData);
          await expect(this.mockFromEntrypoint.uninstallModule(moduleTypeId, moduleMock, deinitData))
            .to.emit(this.mock, 'ModuleUninstalled')
            .withArgs(moduleTypeId, moduleMock)
            .to.emit(moduleMock, 'ModuleUninstalledReceived')
            .withArgs(this.mock, '0x'); // After decoding MODULE_TYPE_FALLBACK, it should remove the fnSig
          await expect(this.mock.isModuleInstalled(moduleTypeId, moduleMock, deinitData)).to.eventually.equal(false);
        });
      }
    });

    describe('execute', function () {
      beforeEach(async function () {
        const moduleMock = await ethers.deployContract('$ERC7579ModuleMock', [MODULE_TYPE_EXECUTOR]);
        await this.mock.$_installModule(MODULE_TYPE_EXECUTOR, moduleMock, '0x');
        this.mockFromEntrypoint = this.mock.connect(await impersonate(entrypoint.target));
        this.mockFromExecutor = this.mock.connect(await impersonate(moduleMock.target));
        await setBalance(this.mock.target, ethers.parseEther('1'));
      });

      it('should revert using execute if the caller is not the canonical entrypoint or the account itself', async function () {
        await expect(
          this.mock
            .connect(this.other)
            .execute(encodeMode({ callType: CALL_TYPE_CALL }), encodeSingle(this.other, 0, '0x')),
        )
          .to.be.revertedWithCustomError(this.mock, 'AccountUnauthorized')
          .withArgs(this.other);
      });

      it('should revert using executeFromExecutor if the caller is not an installed executor', async function () {
        await expect(
          this.mock
            .connect(this.other)
            .executeFromExecutor(encodeMode({ callType: CALL_TYPE_CALL }), encodeSingle(this.other, 0, '0x')),
        )
          .to.be.revertedWithCustomError(this.mock, 'ERC7579UninstalledModule')
          .withArgs(MODULE_TYPE_EXECUTOR, this.other);
      });

      for (const [execFn, mock] of [
        ['execute', 'mockFromEntrypoint'],
        ['executeFromExecutor', 'mockFromExecutor'],
      ]) {
        describe(`executing with ${execFn}`, function () {
          it('should revert if the call type is not supported', async function () {
            await expect(this[mock][execFn](encodeMode({ callType: '0x12' }), encodeSingle(this.other, 0, '0x')))
              .to.be.revertedWithCustomError(this.mock, 'ERC7579UnsupportedCallType')
              .withArgs(ethers.solidityPacked(['bytes1'], ['0x12']));
          });

          describe('single execution', function () {
            it('calls the target with value and args', async function () {
              const value = 0x432;
              const data = encodeSingle(
                this.target,
                value,
                this.target.interface.encodeFunctionData('mockFunctionWithArgs', [42, '0x1234']),
              );

              await expect(this[mock][execFn](encodeMode({ callType: CALL_TYPE_CALL }), data))
                .to.emit(this.target, 'MockFunctionCalledWithArgs')
                .withArgs(42, '0x1234');

              await expect(ethers.provider.getBalance(this.target)).to.eventually.equal(value);
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

              await expect(this[mock][execFn](encodeMode({ callType: CALL_TYPE_BATCH }), data))
                .to.emit(this.target, 'MockFunctionCalledWithArgs')
                .to.emit(this.anotherTarget, 'MockFunctionCalledWithArgs');

              await expect(ethers.provider.getBalance(this.target)).to.eventually.equal(value1);
              await expect(ethers.provider.getBalance(this.anotherTarget)).to.eventually.equal(value2);
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

              await expect(this[mock][execFn](encodeMode({ callType: CALL_TYPE_BATCH, execType: EXEC_TYPE_TRY }), data))
                .to.emit(this.mock, 'ERC7579TryExecuteFail')
                .withArgs(
                  CALL_TYPE_BATCH,
                  ethers.solidityPacked(
                    ['bytes4', 'bytes'],
                    [selector('Error(string)'), coder.encode(['string'], ['CallReceiverMock: reverting'])],
                  ),
                );

              await expect(ethers.provider.getBalance(this.target)).to.eventually.equal(value1);
              await expect(ethers.provider.getBalance(this.anotherTarget)).to.eventually.equal(0);
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
        });
      }
    });
  });
}

module.exports = {
  shouldBehaveLikeAccountCore,
  shouldBehaveLikeAccountHolder,
  shouldBehaveLikeAccountERC7821,
  shouldBehaveLikeAccountERC7579,
};
