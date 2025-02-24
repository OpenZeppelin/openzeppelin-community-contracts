const { expect } = require('chai');
const { ethers, entrypoint } = require('hardhat');
const { loadFixture, time } = require('@nomicfoundation/hardhat-network-helpers');
const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');
const {
  MODULE_TYPE_EXECUTOR,
  encodeMode,
  CALL_TYPE_SINGLE,
  EXEC_TYPE_DEFAULT,
  encodeSingle,
} = require('@openzeppelin/contracts/test/helpers/erc7579');
const { PackedUserOperation } = require('../../../helpers/eip712-types');
const { ERC4337Helper } = require('../../../helpers/erc4337');
const { SocialRecoveryExecutorHelper } = require('../../../helpers/erc7579-modules');
const { SIG_VALIDATION_SUCCESS, SIG_VALIDATION_FAILURE } = require('@openzeppelin/contracts/test/helpers/erc4337');
const { getDomain } = require('@openzeppelin/contracts/test/helpers/eip712');

async function fixture() {
  // ERC-7579 validator
  const validatorMock = await ethers.deployContract('$ERC7579ReconfigurableValidatorMock');

  // ERC-4337 signers
  const initialSigner = ethers.Wallet.createRandom();
  const newSigner = ethers.Wallet.createRandom();

  // ERC-4337 account
  const erc4337Helper = new ERC4337Helper();
  const env = await erc4337Helper.wait();
  const accountMock = await erc4337Helper.newAccount('$AccountERC7579Mock', [
    'AccountERC7579',
    '1',
    validatorMock.target,
    initialSigner.address,
  ]);
  await accountMock.deploy();

  // domain cannot be fetched using getDomain(mock) before the mock is deployed
  const domain = {
    name: 'AccountERC7579',
    version: '1',
    chainId: env.chainId,
    verifyingContract: accountMock.address,
  };

  const signUserOpWithSigner = (userOp, signer) =>
    signer
      .signTypedData(domain, { PackedUserOperation }, userOp.packed)
      .then(signature => Object.assign(userOp, { signature }));

  const userOp = {
    // Use the first 20 bytes from the nonce key (24 bytes) to identify the validator module
    nonce: ethers.zeroPadBytes(ethers.hexlify(validatorMock.target), 32),
  };

  // impersonate ERC-4337 Canonical Entrypoint
  const accountMockFromEntrypoint = accountMock.connect(await impersonate(entrypoint.target));

  // ERC-7579 Social Recovery Executor Module
  const mock = await ethers.deployContract('$SocialRecoveryExecutor', ['SocialRecoveryExecutor', '0.0.1']);

  // ERC-7579 Social Recovery Executor Module Initial Config
  const recoveryConfig = {
    guardians: new Array(3).fill(null).map(() => ethers.Wallet.createRandom()),
    threshold: 2,
    timelock: time.duration.days(1),
  };

  return {
    ...env,
    validatorMock,
    accountMock,
    domain,
    initialSigner,
    newSigner,
    signUserOpWithSigner,
    userOp,
    mock,
    recoveryConfig,
    accountMockFromEntrypoint,
  };
}

describe('SocialRecoveryExecutorModule', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('should not be installed', async function () {
    expect(await this.accountMock.isModuleInstalled(MODULE_TYPE_EXECUTOR, this.mock.target, '0x')).to.equal(false);
  });

  describe('with installed module', function () {
    beforeEach(async function () {
      this.initData = ethers.AbiCoder.defaultAbiCoder().encode(
        ['address[]', 'uint256', 'uint256'],
        [
          this.recoveryConfig.guardians.map(g => g.address),
          this.recoveryConfig.threshold,
          this.recoveryConfig.timelock,
        ],
      );
      await expect(this.accountMockFromEntrypoint.installModule(MODULE_TYPE_EXECUTOR, this.mock.target, this.initData))
        .to.emit(this.accountMock, 'ModuleInstalled')
        .withArgs(MODULE_TYPE_EXECUTOR, this.mock.target)
        .to.emit(this.mock, 'ModuleInstalledReceived')
        .withArgs(this.accountMock.target, this.initData);
    });

    it('should ensure module has been installed', async function () {
      expect(await this.accountMock.isModuleInstalled(MODULE_TYPE_EXECUTOR, this.mock.target, '0x')).to.equal(true);
    });

    it('should be able to uninstall module', async function () {
      await expect(this.accountMockFromEntrypoint.uninstallModule(MODULE_TYPE_EXECUTOR, this.mock.target, '0x'))
        .to.emit(this.accountMock, 'ModuleUninstalled')
        .withArgs(MODULE_TYPE_EXECUTOR, this.mock.target)
        .to.emit(this.mock, 'ModuleUninstalledReceived')
        .withArgs(this.accountMock.target, '0x');

      expect(await this.accountMock.isModuleInstalled(MODULE_TYPE_EXECUTOR, this.mock.target, '0x')).to.equal(false);

      const guardians = await this.mock.getGuardians(this.accountMock.target);
      expect(guardians).to.deep.equal([]);

      const threshold = await this.mock.getThreshold(this.accountMock.target);
      expect(threshold).to.equal(0);

      const timelock = await this.mock.getTimelock(this.accountMock.target);
      expect(timelock).to.equal(0);

      const nonce = await this.mock.nonces(this.accountMock.target);
      expect(nonce).to.equal(0);
    });

    describe('signature validation', function () {
      it('should recognize guardians', async function () {
        const isGuardian = await this.mock.isGuardian(
          this.accountMock.target,
          this.recoveryConfig.guardians[0].address,
        );
        expect(isGuardian).to.equal(true);
      });

      it('should invalidate signatures from invalid guardians', async function () {
        const guardians = this.recoveryConfig.guardians.slice(0, 2);
        const invalidGuardian = ethers.Wallet.createRandom();
        const invalidGuardians = [...guardians, invalidGuardian];

        const message = 'Hello Social Recovery';
        const digest = ethers.hashMessage(message);

        const guardianSignatures = SocialRecoveryExecutorHelper.sortGuardianSignatures(
          invalidGuardians.map(g => ({
            signer: g.address,
            signature: g.signMessage(message),
          })),
        );

        await expect(
          this.mock.validateGuardianSignatures(this.accountMock.target, guardianSignatures, digest),
        ).to.be.revertedWithCustomError(this.mock, 'InvalidGuardianSignature');
      });

      it('should invalidate unsorted guardian signatures', async function () {
        const guardians = this.recoveryConfig.guardians.slice(0, 2);
        const reversedGuardians = guardians.sort().reverse();

        const message = 'Hello Social Recovery';
        const digest = ethers.hashMessage(message);

        const guardianSignatures = reversedGuardians.map(g => ({
          signer: g.address,
          signature: g.signMessage(message),
        }));

        await expect(
          this.mock.validateGuardianSignatures(this.accountMock.target, guardianSignatures, digest),
        ).to.be.revertedWithCustomError(this.mock, 'DuplicatedOrUnsortedGuardianSignatures');
      });

      it('should invalidate duplicate guardian signatures', async function () {
        const guardian = this.recoveryConfig.guardians[0];
        const identicalGuardians = [guardian, guardian];

        const message = 'Hello Social Recovery';
        const digest = ethers.hashMessage(message);

        const guardianSignatures = SocialRecoveryExecutorHelper.sortGuardianSignatures(
          identicalGuardians.map(g => ({
            signer: g.address,
            signature: g.signMessage(message),
          })),
        );

        await expect(
          this.mock.validateGuardianSignatures(this.accountMock.target, guardianSignatures, digest),
        ).to.be.revertedWithCustomError(this.mock, 'DuplicatedOrUnsortedGuardianSignatures');
      });

      it('should fail if threshold is not met', async function () {
        const insufficientGuardians = this.recoveryConfig.guardians.slice(0, this.recoveryConfig.threshold - 1);
        const message = 'Hello Social Recovery';
        const digest = ethers.hashMessage(message);

        const guardianSignatures = SocialRecoveryExecutorHelper.sortGuardianSignatures(
          insufficientGuardians.map(g => ({
            signer: g.address,
            signature: g.signMessage(message),
          })),
        );

        await expect(
          this.mock.validateGuardianSignatures(this.accountMock.target, guardianSignatures, digest),
        ).to.be.revertedWithCustomError(this.mock, 'ThresholdNotMet');
      });

      it('should validate valid guardian signatures', async function () {
        const guardians = this.recoveryConfig.guardians.slice(0, this.recoveryConfig.threshold);
        const message = 'Hello Social Recovery';
        const digest = ethers.hashMessage(message);

        const guardianSignatures = SocialRecoveryExecutorHelper.sortGuardianSignatures(
          guardians.map(g => ({
            signer: g.address,
            signature: g.signMessage(message),
          })),
        );

        await expect(this.mock.validateGuardianSignatures(this.accountMock.target, guardianSignatures, digest)).to.not
          .be.reverted;
      });
    });

    describe('recovery', function () {
      it('status should be not started', async function () {
        const status = await this.mock.getRecoveryStatus(this.accountMock.target);
        expect(status).to.equal(SocialRecoveryExecutorHelper.RecoveryStatus.NotStarted);
      });

      describe('with recovery started', function () {
        beforeEach(async function () {
          const guardians = this.recoveryConfig.guardians.slice(0, this.recoveryConfig.threshold);
          const domain = await getDomain(this.mock);

          const encodedCallToValidatorModule = this.validatorMock.interface.encodeFunctionData('changeSigner', [
            this.newSigner.address,
          ]);
          const recoveryCallData = encodeSingle(this.validatorMock.target, 0, encodedCallToValidatorModule);
          const executionCalldata = this.accountMock.interface.encodeFunctionData('executeFromExecutor', [
            encodeMode(CALL_TYPE_SINGLE, EXEC_TYPE_DEFAULT),
            recoveryCallData,
          ]);

          const message = {
            account: this.accountMock.target,
            nonce: await this.mock.nonces(this.accountMock.target),
            executionCalldata: executionCalldata,
          };

          const guardianSignatures = SocialRecoveryExecutorHelper.sortGuardianSignatures(
            guardians.map(g => ({
              signer: g.address,
              signature: g.signTypedData(domain, SocialRecoveryExecutorHelper.START_RECOVERY_TYPEHASH, message),
            })),
          );

          await expect(this.mock.startRecovery(this.accountMock.target, guardianSignatures, executionCalldata))
            .to.emit(this.mock, 'RecoveryStarted')
            .withArgs(this.accountMock.target);
        });

        it('status should be started', async function () {
          const status = await this.mock.getRecoveryStatus(this.accountMock.target);
          expect(status).to.equal(SocialRecoveryExecutorHelper.RecoveryStatus.Started);
        });

        it('should not be able to start recovery again', async function () {
          await expect(this.mock.startRecovery(this.accountMock.target, [], '0x')).to.be.revertedWithCustomError(
            this.mock,
            'RecoveryAlreadyStarted',
          );
        });

        describe('execute recovery', function () {
          it('should fail to execute if timelock is not met', async function () {
            await expect(this.mock.executeRecovery(this.accountMock.target, '0x')).to.be.revertedWithCustomError(
              this.mock,
              'RecoveryNotReady',
            );
          });

          describe('with timelock met', function () {
            beforeEach(async function () {
              await time.increase(time.duration.days(1));
            });

            it('should fail if the execution calldata differs from the signed by guardians', async function () {
              const differentNewSigner = ethers.Wallet.createRandom();

              const encodedCallToValidatorModule = this.validatorMock.interface.encodeFunctionData('changeSigner', [
                differentNewSigner.address,
              ]);
              const recoveryCallData = encodeSingle(this.validatorMock.target, 0, encodedCallToValidatorModule);
              const executionCalldata = this.accountMock.interface.encodeFunctionData('executeFromExecutor', [
                encodeMode(CALL_TYPE_SINGLE, EXEC_TYPE_DEFAULT),
                recoveryCallData,
              ]);

              await expect(
                this.mock.executeRecovery(this.accountMock.target, executionCalldata),
              ).to.be.revertedWithCustomError(this.mock, 'ExecutionDiffersFromPending');
            });

            it('new signer should not be able to validate himself on the account yet', async function () {
              const operation = await this.accountMock
                .createUserOp(this.userOp)
                .then(op => this.signUserOpWithSigner(op, this.newSigner));

              await expect(
                this.accountMockFromEntrypoint.validateUserOp.staticCall(operation.packed, operation.hash(), 0),
              ).to.eventually.equal(SIG_VALIDATION_FAILURE);
            });

            describe('with recovery executed successfully', function () {
              beforeEach(async function () {
                const encodedCallToValidatorModule = this.validatorMock.interface.encodeFunctionData('changeSigner', [
                  this.newSigner.address,
                ]);
                const recoveryCallData = encodeSingle(this.validatorMock.target, 0, encodedCallToValidatorModule);
                const executionCalldata = this.accountMock.interface.encodeFunctionData('executeFromExecutor', [
                  encodeMode(CALL_TYPE_SINGLE, EXEC_TYPE_DEFAULT),
                  recoveryCallData,
                ]);

                await expect(this.mock.executeRecovery(this.accountMock.target, executionCalldata))
                  .to.emit(this.mock, 'RecoveryExecuted')
                  .withArgs(this.accountMock.target);
              });

              it('should change recovery status to NotStarted', async function () {
                const status = await this.mock.getRecoveryStatus(this.accountMock.target);
                expect(status).to.equal(SocialRecoveryExecutorHelper.RecoveryStatus.NotStarted);
              });

              it('should change the account validator module signer', async function () {
                const signer = await this.validatorMock.getSigner(this.accountMock.target);
                expect(signer).to.equal(this.newSigner.address);
              });

              it('should allow the new signer to get validated on the account', async function () {
                const operation = await this.accountMock
                  .createUserOp(this.userOp)
                  .then(op => this.signUserOpWithSigner(op, this.newSigner));
                expect(
                  await this.accountMockFromEntrypoint.validateUserOp.staticCall(operation.packed, operation.hash(), 0),
                ).to.eq(SIG_VALIDATION_SUCCESS);
              });

              it('should ensure previous signer is not able to validate on the account any more', async function () {
                const operation = await this.accountMock
                  .createUserOp(this.userOp)
                  .then(op => this.signUserOpWithSigner(op, this.initialSigner));
                expect(
                  await this.accountMockFromEntrypoint.validateUserOp.staticCall(operation.packed, operation.hash(), 0),
                ).to.eq(SIG_VALIDATION_FAILURE);
              });
            });
          });
        });

        describe('cancel recovery by the guardians', async function () {
          describe('with cancelled recovery', async function () {
            beforeEach(async function () {
              // allow the guardians to cancel the recovery
              const guardians = this.recoveryConfig.guardians.slice(0, this.recoveryConfig.threshold);
              const domain = await getDomain(this.mock);

              const message = {
                account: this.accountMock.target,
                nonce: await this.mock.nonces(this.accountMock.target),
              };

              const guardianSignatures = SocialRecoveryExecutorHelper.sortGuardianSignatures(
                guardians.map(g => ({
                  signer: g.address,
                  signature: g.signTypedData(domain, SocialRecoveryExecutorHelper.CANCEL_RECOVERY_TYPEHASH, message),
                })),
              );

              await expect(this.mock.cancelRecovery(this.accountMock.target, guardianSignatures))
                .to.emit(this.mock, 'RecoveryCancelled')
                .withArgs(this.accountMock.target);
            });

            it('should change recovery status to NotStarted', async function () {
              const status = await this.mock.getRecoveryStatus(this.accountMock.target);
              expect(status).to.equal(SocialRecoveryExecutorHelper.RecoveryStatus.NotStarted);
            });

            it('should not be able to cancel again', async function () {
              await expect(this.mock.cancelRecovery(this.accountMock.target, [])).to.be.revertedWithCustomError(
                this.mock,
                'RecoveryNotStarted',
              );
            });
          });
        });

        describe('cancel recovery by the Account', async function () {
          describe('with cancelled recovery', async function () {
            beforeEach(async function () {
              await expect(
                this.accountMockFromEntrypoint.execute(
                  encodeMode(CALL_TYPE_SINGLE, EXEC_TYPE_DEFAULT),
                  encodeSingle(this.mock.target, 0, this.mock.interface.encodeFunctionData('cancelRecovery()')),
                ),
              )
                .to.emit(this.mock, 'RecoveryCancelled')
                .withArgs(this.accountMock.target);
            });

            it('should change recovery status to NotStarted', async function () {
              const status = await this.mock.getRecoveryStatus(this.accountMock.target);
              expect(status).to.equal(SocialRecoveryExecutorHelper.RecoveryStatus.NotStarted);
            });

            it('should resist replay attacks via nonce protection', async function () {
              // guardians attempt to reuse initial signatures to startRecovery again
              const alreadyUsedNonce = (await this.mock.nonces(this.accountMock.target)) - 1n;
              const guardians = this.recoveryConfig.guardians;
              const domain = await getDomain(this.mock);

              const encodedCallToValidatorModule = this.validatorMock.interface.encodeFunctionData('changeSigner', [
                this.newSigner.address,
              ]);

              const recoveryCallData = encodeSingle(this.validatorMock.target, 0, encodedCallToValidatorModule);

              const executionCalldata = this.accountMock.interface.encodeFunctionData('executeFromExecutor', [
                encodeMode(CALL_TYPE_SINGLE, EXEC_TYPE_DEFAULT),
                recoveryCallData,
              ]);

              const message = {
                account: this.accountMock.target,
                nonce: alreadyUsedNonce,
                executionCalldata: executionCalldata,
              };

              const guardianSignatures = SocialRecoveryExecutorHelper.sortGuardianSignatures(
                guardians.map(g => ({
                  signer: g.address,
                  signature: g.signTypedData(domain, SocialRecoveryExecutorHelper.START_RECOVERY_TYPEHASH, message),
                })),
              );

              await expect(
                this.mock.startRecovery(this.accountMock.target, guardianSignatures, executionCalldata),
              ).to.be.revertedWithCustomError(this.mock, 'InvalidGuardianSignature');
            });
          });
        });
      });

      describe('module configuration', function () {
        it('should be able to add a guardian', async function () {
          const newGuardian = ethers.Wallet.createRandom();
          await expect(
            this.accountMockFromEntrypoint.execute(
              encodeMode(CALL_TYPE_SINGLE, EXEC_TYPE_DEFAULT),
              encodeSingle(
                this.mock.target,
                0,
                this.mock.interface.encodeFunctionData('addGuardian', [newGuardian.address]),
              ),
            ),
          )
            .to.emit(this.mock, 'GuardianAdded')
            .withArgs(this.accountMock.target, newGuardian.address);

          const isGuardian = await this.mock.isGuardian(this.accountMock.target, newGuardian.address);
          expect(isGuardian).to.equal(true);
        });

        it('should be able to remove a guardian', async function () {
          const guardianToRemove = this.recoveryConfig.guardians[0];
          await expect(
            this.accountMockFromEntrypoint.execute(
              encodeMode(CALL_TYPE_SINGLE, EXEC_TYPE_DEFAULT),
              encodeSingle(
                this.mock.target,
                0,
                this.mock.interface.encodeFunctionData('removeGuardian', [guardianToRemove.address]),
              ),
            ),
          )
            .to.emit(this.mock, 'GuardianRemoved')
            .withArgs(this.accountMock.target, guardianToRemove.address);

          const isGuardian = await this.mock.isGuardian(this.accountMock.target, guardianToRemove.address);
          expect(isGuardian).to.equal(false);
        });

        it('should be able to change the threshold', async function () {
          const newThreshold = this.recoveryConfig.threshold + 1;
          await expect(
            this.accountMockFromEntrypoint.execute(
              encodeMode(CALL_TYPE_SINGLE, EXEC_TYPE_DEFAULT),
              encodeSingle(
                this.mock.target,
                0,
                this.mock.interface.encodeFunctionData('changeThreshold', [newThreshold]),
              ),
            ),
          )
            .to.emit(this.mock, 'ThresholdChanged')
            .withArgs(this.accountMock.target, newThreshold);

          const threshold = await this.mock.getThreshold(this.accountMock.target);
          expect(threshold).to.equal(newThreshold);
        });

        describe('changing timelock', function () {
          it('should fail if timelock is zero', async function () {
            await expect(
              this.accountMockFromEntrypoint.execute(
                encodeMode(CALL_TYPE_SINGLE, EXEC_TYPE_DEFAULT),
                encodeSingle(this.mock.target, 0, this.mock.interface.encodeFunctionData('changeTimelock', [0])),
              ),
            ).to.be.revertedWithCustomError(this.mock, 'InvalidTimelock');
          });

          it('should be able to change the timelock', async function () {
            const newTimelock = this.recoveryConfig.timelock + 1;
            await expect(
              this.accountMockFromEntrypoint.execute(
                encodeMode(CALL_TYPE_SINGLE, EXEC_TYPE_DEFAULT),
                encodeSingle(
                  this.mock.target,
                  0,
                  this.mock.interface.encodeFunctionData('changeTimelock', [newTimelock]),
                ),
              ),
            )
              .to.emit(this.mock, 'TimelockChanged')
              .withArgs(this.accountMock.target, newTimelock);

            const timelock = await this.mock.getTimelock(this.accountMock.target);
            expect(timelock).to.equal(newTimelock);
          });
        });
      });
    });
  });
  describe('module metadata', function () {
    it('should match the correct module type', async function () {
      expect(await this.mock.isModuleType(MODULE_TYPE_EXECUTOR)).to.equal(true);
    });
  });
});
