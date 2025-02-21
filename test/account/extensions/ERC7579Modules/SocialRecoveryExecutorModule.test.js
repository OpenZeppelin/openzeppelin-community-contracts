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
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const accountMock = await helper.newAccount('$AccountERC7579Mock', [
    'AccountERC7579',
    '1',
    validatorMock.target,
    ethers.solidityPacked(['address'], [initialSigner.address]),
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

  // ERC-7579 Social Recovery Executor Module Initial Config
  const recoveryConfig = {
    guardians: new Array(3).fill(null).map(() => ethers.Wallet.createRandom()),
    threshold: 2,
    timelock: time.duration.days(1),
  };

  // ERC-7579 Social Recovery Executor Module
  const mock = await ethers.deployContract('$SocialRecoveryExecutor');

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

      const nonce = await this.mock.getNonce(this.accountMock.target);
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

      it('should validate one guardian signature', async function () {
        const guardian = this.recoveryConfig.guardians[0];

        const signature = await guardian.signTypedData(
          await getDomain(this.mock),
          SocialRecoveryExecutorHelper.RECOVERY_MESSAGE_TYPE,
          {
            account: this.accountMock.target,
            nonce: await this.mock.getNonce(this.accountMock.target),
          },
        );

        const guardianSignature = {
          signer: guardian.address,
          signature: signature,
        };

        const isValidSignature = await this.mock.guardianSignatureIsValid(this.accountMock.target, guardianSignature);
        expect(isValidSignature).to.equal(true);
      });

      it('should validate multiple guardian signatures', async function () {
        const guardians = this.recoveryConfig.guardians;
        const domain = await getDomain(this.mock);
        const message = {
          account: this.accountMock.target,
          nonce: await this.mock.getNonce(this.accountMock.target),
        };

        const signatures = await Promise.all(
          guardians.map(guardian =>
            guardian.signTypedData(domain, SocialRecoveryExecutorHelper.RECOVERY_MESSAGE_TYPE, message),
          ),
        );

        const guardianSignatures = guardians.map((g, i) => ({
          signer: g.address,
          signature: signatures[i],
        }));

        const signaturesAreValid = await this.mock.guardianSignaturesAreValid(
          this.accountMock.target,
          guardianSignatures,
        );
        expect(signaturesAreValid).to.equal(true);
      });

      it('should invalidate identical guardian signatures', async function () {
        const guardian = this.recoveryConfig.guardians[0];
        const identicalGuardians = [guardian, guardian];

        const domain = await getDomain(this.mock);
        const message = { account: this.accountMock.target, nonce: await this.mock.getNonce(this.accountMock.target) };

        const signatures = await Promise.all(
          identicalGuardians.map(guardian =>
            guardian.signTypedData(domain, SocialRecoveryExecutorHelper.RECOVERY_MESSAGE_TYPE, message),
          ),
        );

        const guardianSignatures = identicalGuardians.map((g, i) => ({
          signer: g.address,
          signature: signatures[i],
        }));

        const signaturesAreValid = await this.mock.guardianSignaturesAreValid(
          this.accountMock.target,
          guardianSignatures,
        );
        expect(signaturesAreValid).to.equal(false);
      });

      it('should invalidate invalid guardian signatures', async function () {
        const guardians = this.recoveryConfig.guardians.slice(0, 2);
        const invalidGuardian = ethers.Wallet.createRandom();
        const invalidGuardians = [...guardians, invalidGuardian];

        const domain = await getDomain(this.mock);
        const message = { account: this.accountMock.target, nonce: await this.mock.getNonce(this.accountMock.target) };

        const signatures = await Promise.all(
          invalidGuardians.map(guardian =>
            guardian.signTypedData(domain, SocialRecoveryExecutorHelper.RECOVERY_MESSAGE_TYPE, message),
          ),
        );

        const guardianSignatures = invalidGuardians.map((g, i) => ({
          signer: g.address,
          signature: signatures[i],
        }));

        const signaturesAreValid = await this.mock.guardianSignaturesAreValid(
          this.accountMock.target,
          guardianSignatures,
        );
        expect(signaturesAreValid).to.equal(false);
      });
    });

    describe('recovery', function () {
      describe('start recovery', function () {
        it('status should be not started', async function () {
          const status = await this.mock.getRecoveryStatus(this.accountMock.target);
          expect(status).to.equal(SocialRecoveryExecutorHelper.RecoveryStatus.NotStarted);
        });

        it('should not be able to start recovery if threshold is not met', async function () {
          const insufficientGuardians = this.recoveryConfig.guardians.slice(0, this.recoveryConfig.threshold - 1);
          const domain = await getDomain(this.mock);
          const message = {
            account: this.accountMock.target,
            nonce: await this.mock.getNonce(this.accountMock.target),
          };

          const signatures = await Promise.all(
            insufficientGuardians.map(guardian =>
              guardian.signTypedData(domain, SocialRecoveryExecutorHelper.RECOVERY_MESSAGE_TYPE, message),
            ),
          );

          const guardianSignatures = insufficientGuardians.map((g, i) => ({
            signer: g.address,
            signature: signatures[i],
          }));

          await expect(
            this.mock.startRecovery(this.accountMock.target, guardianSignatures),
          ).to.be.revertedWithCustomError(this.mock, 'ThresholdNotMet');
        });
      });

      describe('with recovery started', function () {
        beforeEach(async function () {
          const guardians = this.recoveryConfig.guardians.slice(0, this.recoveryConfig.threshold);
          const domain = await getDomain(this.mock);
          const message = {
            account: this.accountMock.target,
            nonce: await this.mock.getNonce(this.accountMock.target),
          };

          const signatures = await Promise.all(
            guardians.map(guardian =>
              guardian.signTypedData(domain, SocialRecoveryExecutorHelper.RECOVERY_MESSAGE_TYPE, message),
            ),
          );

          const guardianSignatures = guardians.map((g, i) => ({
            signer: g.address,
            signature: signatures[i],
          }));

          await expect(this.mock.startRecovery(this.accountMock.target, guardianSignatures))
            .to.emit(this.mock, 'RecoveryStarted')
            .withArgs(this.accountMock.target);
        });

        it('status should be started', async function () {
          const status = await this.mock.getRecoveryStatus(this.accountMock.target);
          expect(status).to.equal(SocialRecoveryExecutorHelper.RecoveryStatus.Started);
        });

        it('should not be able to start recovery again', async function () {
          await expect(this.mock.startRecovery(this.accountMock.target, [])).to.be.revertedWithCustomError(
            this.mock,
            'RecoveryAlreadyStarted',
          );
        });

        describe('execute recovery', function () {
          it('should fail to execute if timelock is not met', async function () {
            const guardians = this.recoveryConfig.guardians;
            const domain = await getDomain(this.mock);
            const message = {
              account: this.accountMock.target,
              nonce: await this.mock.getNonce(this.accountMock.target),
            };

            const signatures = await Promise.all(
              guardians.map(guardian =>
                guardian.signTypedData(domain, SocialRecoveryExecutorHelper.RECOVERY_MESSAGE_TYPE, message),
              ),
            );

            const guardianSignatures = guardians.map((g, i) => ({
              signer: g.address,
              signature: signatures[i],
            }));

            await expect(
              this.mock.executeRecovery(this.accountMock.target, guardianSignatures, '0x'),
            ).to.be.revertedWithCustomError(this.mock, 'RecoveryNotReady');
          });

          describe('with timelock met', function () {
            beforeEach(async function () {
              await time.increase(time.duration.days(1));
            });

            it('should fail if threshold is not met', async function () {
              const insufficientGuardians = this.recoveryConfig.guardians.slice(0, this.recoveryConfig.threshold - 1);
              const domain = await getDomain(this.mock);
              const message = {
                account: this.accountMock.target,
                nonce: await this.mock.getNonce(this.accountMock.target),
              };

              const signatures = await Promise.all(
                insufficientGuardians.map(guardian =>
                  guardian.signTypedData(domain, SocialRecoveryExecutorHelper.RECOVERY_MESSAGE_TYPE, message),
                ),
              );

              const guardianSignatures = insufficientGuardians.map((g, i) => ({
                signer: g.address,
                signature: signatures[i],
              }));

              await expect(
                this.mock.executeRecovery(this.accountMock.target, guardianSignatures, '0x'),
              ).to.be.revertedWithCustomError(this.mock, 'ThresholdNotMet');
            });

            it('should fail if invalid recovery calladata is passed', async function () {
              const guardians = this.recoveryConfig.guardians;
              const domain = await getDomain(this.mock);
              const message = {
                account: this.accountMock.target,
                nonce: await this.mock.getNonce(this.accountMock.target),
              };

              const signatures = await Promise.all(
                guardians.map(guardian =>
                  guardian.signTypedData(domain, SocialRecoveryExecutorHelper.RECOVERY_MESSAGE_TYPE, message),
                ),
              );

              const guardianSignatures = guardians.map((g, i) => ({
                signer: g.address,
                signature: signatures[i],
              }));

              await expect(
                this.mock.executeRecovery(this.accountMock.target, guardianSignatures, '0x'),
              ).to.be.revertedWithCustomError(this.mock, 'InvalidRecoveryCallData');
            });

            // this prevents guardians from reconfiguring the Executor Module.
            it('should fail if the target is this Executor Module', async function () {
              const guardians = this.recoveryConfig.guardians;
              const domain = await getDomain(this.mock);
              const message = {
                account: this.accountMock.target,
                nonce: await this.mock.getNonce(this.accountMock.target),
              };
              const signatures = await Promise.all(
                guardians.map(guardian =>
                  guardian.signTypedData(domain, SocialRecoveryExecutorHelper.RECOVERY_MESSAGE_TYPE, message),
                ),
              );
              const guardianSignatures = guardians.map((g, i) => ({
                signer: g.address,
                signature: signatures[i],
              }));

              // attempt to reconfigure the Executor Module should fail because is not an installed validator module
              const newGuardian = ethers.Wallet.createRandom();
              const encodedCallToExecutor = this.mock.interface.encodeFunctionData('addGuardian', [
                newGuardian.address,
              ]);

              const executionData = encodeSingle(this.mock.target, 0, encodedCallToExecutor);

              await expect(
                this.mock.executeRecovery(this.accountMock.target, guardianSignatures, executionData),
              ).to.be.revertedWithCustomError(this.mock, 'InvalidInstalledValidatorModule');
            });

            // this prevents guardians from doing anything else than reconfiguring an installed Validator Module.
            it('should fail if target is not an installed Validator Module', async function () {
              const guardians = this.recoveryConfig.guardians;
              const domain = await getDomain(this.mock);
              const message = {
                account: this.accountMock.target,
                nonce: await this.mock.getNonce(this.accountMock.target),
              };
              const signatures = await Promise.all(
                guardians.map(guardian =>
                  guardian.signTypedData(domain, SocialRecoveryExecutorHelper.RECOVERY_MESSAGE_TYPE, message),
                ),
              );
              const guardianSignatures = guardians.map((g, i) => ({
                signer: g.address,
                signature: signatures[i],
              }));

              const anotherValidatorMock = await ethers.deployContract('$ERC7579ReconfigurableValidatorMock');

              const encodedCallToInvalidInstalledValidatorModule = anotherValidatorMock.interface.encodeFunctionData(
                'changeSigner',
                [this.newSigner.address],
              );

              const executionData = encodeSingle(
                anotherValidatorMock.target,
                0,
                encodedCallToInvalidInstalledValidatorModule,
              );

              await expect(
                this.mock.executeRecovery(this.accountMock.target, guardianSignatures, executionData),
              ).to.be.revertedWithCustomError(this.mock, 'InvalidInstalledValidatorModule');
            });

            it('should resist replay attacks via nonce protection', async function () {
              const guardians = this.recoveryConfig.guardians;
              const domain = await getDomain(this.mock);
              const message = {
                account: this.accountMock.target,
                nonce: (await this.mock.getNonce(this.accountMock.target)) - 1n,
              };

              const signatures = await Promise.all(
                guardians.map(guardian =>
                  guardian.signTypedData(domain, SocialRecoveryExecutorHelper.RECOVERY_MESSAGE_TYPE, message),
                ),
              );

              const guardianSignatures = guardians.map((g, i) => ({
                signer: g.address,
                signature: signatures[i],
              }));

              const encodedCallToValidatorModule = this.validatorMock.interface.encodeFunctionData('changeSigner', [
                this.newSigner.address,
              ]);

              const executionData = encodeSingle(this.validatorMock.target, 0, encodedCallToValidatorModule);

              await expect(
                this.mock.executeRecovery(this.accountMock.target, guardianSignatures, executionData),
              ).to.be.revertedWithCustomError(this.mock, 'InvalidGuardianSignatures');
            });

            describe('execute recovery successfully', function () {
              beforeEach(async function () {
                const guardians = this.recoveryConfig.guardians;
                const domain = await getDomain(this.mock);
                const message = {
                  account: this.accountMock.target,
                  nonce: await this.mock.getNonce(this.accountMock.target),
                };
                const signatures = await Promise.all(
                  guardians.map(guardian =>
                    guardian.signTypedData(domain, SocialRecoveryExecutorHelper.RECOVERY_MESSAGE_TYPE, message),
                  ),
                );

                const guardianSignatures = guardians.map((g, i) => ({
                  signer: g.address,
                  signature: signatures[i],
                }));

                const encodedCallToValidatorModule = this.validatorMock.interface.encodeFunctionData('changeSigner', [
                  this.newSigner.address,
                ]);

                const executionData = encodeSingle(this.validatorMock.target, 0, encodedCallToValidatorModule);

                await expect(this.mock.executeRecovery(this.accountMock.target, guardianSignatures, executionData))
                  .to.emit(this.mock, 'RecoveryExecuted')
                  .withArgs(this.accountMock.target, this.validatorMock.target);
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

        describe('cancel recovery', async function () {
          /**
           * @dev Cancel recovery requires the transaction sender to be the account whose recovery is being cancelled.
           * Thus, the only way to cancel recovery is via the Account being called by the Canonical EntryPoint, and validated through a Validator Module.
           */
          it('should fail if a guardian or any non-signer attempts to cancel recovery', async function () {
            const operation = await this.accountMock
              .createUserOp(this.userOp)
              .then(op => this.signUserOpWithSigner(op, this.recoveryConfig.guardians[0]));

            await expect(
              this.accountMockFromEntrypoint.validateUserOp.staticCall(operation.packed, operation.hash(), 0),
            ).to.eventually.equal(SIG_VALIDATION_FAILURE);
          });

          it('signer should be able to cancel recovery', async function () {
            const operation = await this.accountMock
              .createUserOp(this.userOp)
              .then(op => this.signUserOpWithSigner(op, this.initialSigner));

            // 1. EntryPoint should validate the userOp against the account and validator module
            await expect(
              this.accountMockFromEntrypoint.validateUserOp.staticCall(operation.packed, operation.hash(), 0),
            ).to.eventually.equal(SIG_VALIDATION_SUCCESS);

            // 2. Encode the execute call with mode and executionCallData
            await expect(
              this.accountMockFromEntrypoint.execute(
                encodeMode(CALL_TYPE_SINGLE, EXEC_TYPE_DEFAULT),
                ethers.solidityPacked(
                  ['address', 'uint256', 'bytes'],
                  [this.mock.target, 0, this.mock.interface.encodeFunctionData('cancelRecovery')],
                ),
              ),
            )
              .to.emit(this.mock, 'RecoveryCancelled')
              .withArgs(this.accountMock.target);

            expect(await this.mock.getRecoveryStatus(this.accountMock.target)).to.equal(
              SocialRecoveryExecutorHelper.RecoveryStatus.NotStarted,
            );
          });
        });
      });

      describe('module configuration', function () {
        it('guardian or any non-signer should not be able to configure the module', async function () {
          const operation = await this.accountMock
            .createUserOp(this.userOp)
            .then(op => this.signUserOpWithSigner(op, this.recoveryConfig.guardians[0]));

          await expect(
            this.accountMockFromEntrypoint.validateUserOp.staticCall(operation.packed, operation.hash(), 0),
          ).to.eventually.equal(SIG_VALIDATION_FAILURE);
        });

        it('should be able to add a guardian', async function () {
          const newGuardian = ethers.Wallet.createRandom();
          await expect(
            this.accountMockFromEntrypoint.execute(
              encodeMode(CALL_TYPE_SINGLE, EXEC_TYPE_DEFAULT),
              ethers.solidityPacked(
                ['address', 'uint256', 'bytes'],
                [this.mock.target, 0, this.mock.interface.encodeFunctionData('addGuardian', [newGuardian.address])],
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
              ethers.solidityPacked(
                ['address', 'uint256', 'bytes'],
                [
                  this.mock.target,
                  0,
                  this.mock.interface.encodeFunctionData('removeGuardian', [guardianToRemove.address]),
                ],
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
              ethers.solidityPacked(
                ['address', 'uint256', 'bytes'],
                [this.mock.target, 0, this.mock.interface.encodeFunctionData('changeThreshold', [newThreshold])],
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
                ethers.solidityPacked(
                  ['address', 'uint256', 'bytes'],
                  [this.mock.target, 0, this.mock.interface.encodeFunctionData('changeTimelock', [0])],
                ),
              ),
            ).to.be.revertedWithCustomError(this.mock, 'InvalidTimelock');
          });

          it('should be able to change the timelock', async function () {
            const newTimelock = this.recoveryConfig.timelock + 1;
            await expect(
              this.accountMockFromEntrypoint.execute(
                encodeMode(CALL_TYPE_SINGLE, EXEC_TYPE_DEFAULT),
                ethers.solidityPacked(
                  ['address', 'uint256', 'bytes'],
                  [this.mock.target, 0, this.mock.interface.encodeFunctionData('changeTimelock', [newTimelock])],
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

    it('should return the correct module name', async function () {
      expect(await this.mock.name()).to.equal('SocialRecoveryExecutor');
    });
    it('should return the correct module version', async function () {
      expect(await this.mock.version()).to.equal('0.0.1');
    });
  });
});
