/* global network */
const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

async function fixture() {
  const [pauser] = await ethers.getSigners();

  const mock = await ethers.deployContract('PausableMock');

  return { pauser, mock };
}

describe('Pausable', function () {
  let pauseDuration = 10;

  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('when unpaused', function () {
    beforeEach(async function () {
      expect(await this.mock.paused()).to.be.false;
    });

    it('can perform normal process in non-pause', async function () {
      expect(await this.mock.count()).to.equal(0n);

      await this.mock.normalProcess();
      expect(await this.mock.count()).to.equal(1n);
    });

    it('cannot take drastic measure in non-pause', async function () {
      await expect(this.mock.drasticMeasure()).to.be.revertedWithCustomError(this.mock, 'ExpectedPause');

      expect(await this.mock.drasticMeasureTaken()).to.be.false;
    });

    describe('when paused', function () {
      beforeEach(async function () {
        this.tx = await this.mock.pause();
      });

      it('emits a Paused event', async function () {
        await expect(this.tx).to.emit(this.mock, 'Paused').withArgs(this.pauser, 0);
      });

      it('does not set pause deadline duration', async function () {
        expect(await this.mock.getPausedUntilDeadline()).to.equal(0);
      });

      it('cannot perform normal process in pause', async function () {
        await expect(this.mock.normalProcess()).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
      });

      it('can take a drastic measure in a pause', async function () {
        await this.mock.drasticMeasure();
        expect(await this.mock.drasticMeasureTaken()).to.be.true;
      });

      it('reverts when re-pausing with pause', async function () {
        await expect(this.mock.pause()).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
      });

      it('reverts when re-pausing with pauseUntil', async function () {
        await expect(this.mock.pauseUntil(pauseDuration)).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
      });

      describe('unpause', function () {
        it('is unpausable by the pauser', async function () {
          await this.mock.unpause();
          expect(await this.mock.paused()).to.be.false;
        });

        describe('when unpaused', function () {
          beforeEach(async function () {
            this.tx = await this.mock.unpause();
          });

          it('emits an Unpaused event', async function () {
            await expect(this.tx).to.emit(this.mock, 'Unpaused').withArgs(this.pauser);
          });

          it('does not set pause deadline duration', async function () {
            expect(await this.mock.getPausedUntilDeadline()).to.equal(0);
          });

          it('should resume allowing normal process', async function () {
            expect(await this.mock.count()).to.equal(0n);
            await this.mock.normalProcess();
            expect(await this.mock.count()).to.equal(1n);
          });

          it('should prevent drastic measure', async function () {
            await expect(this.mock.drasticMeasure()).to.be.revertedWithCustomError(this.mock, 'ExpectedPause');
          });

          it('reverts when re-unpausing with unpause', async function () {
            await expect(this.mock.unpause()).to.be.revertedWithCustomError(this.mock, 'ExpectedPause');
          });
        });
      });
    });

    describe('when pausedUntil', function () {
      beforeEach(async function () {
        const [, executionTimestamp] = await this.mock.getPausedUntilDeadlineAndTimestamp();
        const pauseDeadline = parseInt(pauseDuration) + parseInt(executionTimestamp);
        this.tx = await this.mock.pauseUntil(pauseDeadline);
      });

      it('emits a Paused event', async function () {
        const [unpauseDeadline] = await this.mock.getPausedUntilDeadlineAndTimestamp();
        await expect(this.tx).to.emit(this.mock, 'Paused').withArgs(this.pauser, unpauseDeadline);
      });

      it('sets pause deadline and is equal to desired deadline', async function () {
        const [unpauseDeadline, executionTimestamp] = await this.mock.getPausedUntilDeadlineAndTimestamp();
        expect(unpauseDeadline).to.not.equal(0);
        // wee need to do -1 because in the before each the pauseUntil tx increases the timestamp by 1
        const expectedUnpauseDeadline = parseInt(pauseDuration) + parseInt(executionTimestamp) - 1;
        const unpausedDeadlineInt = parseInt(unpauseDeadline);
        expect(unpausedDeadlineInt).to.equal(expectedUnpauseDeadline);
      });

      it('cannot perform normal process in pause', async function () {
        await expect(this.mock.normalProcess()).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
      });

      it('can take a drastic measure in a pause', async function () {
        await this.mock.drasticMeasure();
        expect(await this.mock.drasticMeasureTaken()).to.be.true;
      });

      it('reverts when re-pausing with pause', async function () {
        await expect(this.mock.pause()).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
      });

      it('reverts when re-pausing with pauseUntil', async function () {
        // as it should revert we dont care in this test if pauseDuration is used instead of a deadline
        await expect(this.mock.pauseUntil(pauseDuration)).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
        // checking for pausing 0 seconds too
        await expect(this.mock.pauseUntil(pauseDuration - pauseDuration)).to.be.revertedWithCustomError(
          this.mock,
          'EnforcedPause',
        );
      });

      describe('unpaused', function () {
        it('is unpausable by the pauser', async function () {
          await this.mock.unpause();
          expect(await this.mock.paused()).to.be.false;
        });

        describe('before pause duration passed', function () {
          beforeEach(async function () {
            this.tx = await this.mock.unpause();
          });

          it('emits an Unpaused event', async function () {
            await expect(this.tx).to.emit(this.mock, 'Unpaused').withArgs(this.pauser);
          });

          it('does not set pause deadline', async function () {
            expect(await this.mock.getPausedUntilDeadline()).to.equal(0);
          });

          it('should resume allowing normal process', async function () {
            expect(await this.mock.count()).to.equal(0n);
            await this.mock.normalProcess();
            expect(await this.mock.count()).to.equal(1n);
          });

          it('should prevent drastic measure', async function () {
            await expect(this.mock.drasticMeasure()).to.be.revertedWithCustomError(this.mock, 'ExpectedPause');
          });

          it('reverts when re-unpausing with unpause', async function () {
            await expect(this.mock.unpause()).to.be.revertedWithCustomError(this.mock, 'ExpectedPause');
          });
        });

        describe('after pause duration passed', function () {
          beforeEach(async function () {
            await network.provider.send('evm_increaseTime', [pauseDuration]);
            await network.provider.send('evm_mine');
          });

          it('reverts as contract automatically unpauses', async function () {
            await expect(this.mock.unpause()).to.be.revertedWithCustomError(this.mock, 'ExpectedPause');
          });
        });
      });

      describe('paused after pause duration passed', function () {
        beforeEach(async function () {
          await network.provider.send('evm_increaseTime', [pauseDuration]);
          await network.provider.send('evm_mine');
          this.tx = await this.mock.pause();
        });

        it('emits a Paused event', async function () {
          await expect(this.tx).to.emit(this.mock, 'Paused').withArgs(this.pauser, 0);
        });

        it('does not set pause deadline', async function () {
          expect(await this.mock.getPausedUntilDeadline()).to.equal(0);
        });

        it('cannot perform normal process in pause', async function () {
          await expect(this.mock.normalProcess()).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
        });

        it('can take a drastic measure in a pause', async function () {
          await this.mock.drasticMeasure();
          expect(await this.mock.drasticMeasureTaken()).to.be.true;
        });

        it('reverts when re-pausing with pause', async function () {
          await expect(this.mock.pause()).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
        });

        it('reverts when re-pausing with pauseUntil', async function () {
          // as it should revert we dont care in this test if pauseDuration is used instead of a deadline
          await expect(this.mock.pauseUntil(pauseDuration)).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
          // checking for pausing 0 seconds too
          await expect(this.mock.pauseUntil(pauseDuration - pauseDuration)).to.be.revertedWithCustomError(
            this.mock,
            'EnforcedPause',
          );
        });
      });

      describe('pausedUntil after pause duration passed', function () {
        beforeEach(async function () {
          // Increase time and mine a block
          await network.provider.send('evm_increaseTime', [pauseDuration]);
          await network.provider.send('evm_mine');
          // Fetch the updated execution timestamp after mining
          const [, executionTimestampAfter] = await this.mock.getPausedUntilDeadlineAndTimestamp();
          const pauseDeadline = parseInt(pauseDuration) + parseInt(executionTimestampAfter);
          this.tx = await this.mock.pauseUntil(pauseDeadline);
        });

        it('emits a Paused event', async function () {
          const [, executionTimestamp] = await this.mock.getPausedUntilDeadlineAndTimestamp();
          // wee need to do -1 because in the before each the pauseUntil tx increases the timestamp by 1
          const expectedUnpauseDeadline = parseInt(pauseDuration) + parseInt(executionTimestamp) - 1;
          await expect(this.tx).to.emit(this.mock, 'Paused').withArgs(this.pauser, expectedUnpauseDeadline);
        });

        it('sets pause deadline and is equal to desired deadline', async function () {
          const [unpauseDeadline, executionTimestamp] = await this.mock.getPausedUntilDeadlineAndTimestamp();
          expect(unpauseDeadline).to.not.equal(0);
          // wee need to do -1 because in the before each the pauseUntil tx increases the timestamp by 1
          const expectedUnpauseDeadline = parseInt(pauseDuration) + parseInt(executionTimestamp) - 1;
          const unpausedDeadlineInt = parseInt(unpauseDeadline);
          expect(unpausedDeadlineInt).to.equal(expectedUnpauseDeadline);
        });

        it('cannot perform normal process in pause', async function () {
          await expect(this.mock.normalProcess()).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
        });

        it('can take a drastic measure in a pause', async function () {
          await this.mock.drasticMeasure();
          expect(await this.mock.drasticMeasureTaken()).to.be.true;
        });

        it('reverts when re-pausing with pause', async function () {
          await expect(this.mock.pause()).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
        });

        it('reverts when re-pausing with pauseUntil', async function () {
          // as it should revert we dont care in this test if pauseDuration is used instead of a deadline
          await expect(this.mock.pauseUntil(pauseDuration)).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
          // checking for pausing 0 seconds too
          await expect(this.mock.pauseUntil(pauseDuration - pauseDuration)).to.be.revertedWithCustomError(
            this.mock,
            'EnforcedPause',
          );
        });
      });
    });
  });
});
