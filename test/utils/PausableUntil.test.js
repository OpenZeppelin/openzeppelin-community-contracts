const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const time = require('@openzeppelin/contracts/test/helpers/time');
const { MAX_UINT48 } = require('@openzeppelin/contracts/test/helpers/constants');

const PAUSE_DURATION = 10n;

async function checkPaused(withDeadline = false) {
  it('reported state is correct', async function () {
    await expect(this.mock.paused()).to.eventually.be.true;
  });

  it('check deadline value', async function () {
    await expect(this.mock.$_unpauseDeadline()).to.eventually.equal(withDeadline ? this.deadline : 0n);
  });

  it('whenNotPaused modifier reverts', async function () {
    await expect(this.mock.canCallWhenNotPaused()).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
  });

  it('whenPaused modifier does not reverts', async function () {
    await expect(this.mock.canCallWhenPaused()).to.be.not.reverted;
  });

  it('reverts when pausing with _pause', async function () {
    await expect(this.mock.$_pause()).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
  });

  it('reverts when pausing with _pauseUntil', async function () {
    await expect(this.mock.$_pauseUntil(MAX_UINT48)).to.be.revertedWithCustomError(this.mock, 'EnforcedPause');
  });
}

async function checkUnpaused(strictDealine = true) {
  it('reported state is correct', async function () {
    await expect(this.mock.paused()).to.eventually.be.false;
  });

  if (strictDealine) {
    it('deadline is cleared', async function () {
      await expect(this.mock.$_unpauseDeadline()).to.eventually.equal(0n);
    });
  }

  it('whenNotPaused modifier does not revert', async function () {
    await expect(this.mock.canCallWhenNotPaused()).to.be.not.reverted;
  });

  it('whenPaused modifier reverts', async function () {
    await expect(this.mock.canCallWhenPaused()).to.be.revertedWithCustomError(this.mock, 'ExpectedPause');
  });

  it('reverts when unpausing with _unpause', async function () {
    await expect(this.mock.$_unpause()).to.be.revertedWithCustomError(this.mock, 'ExpectedPause');
  });
}

async function fixture() {
  const [pauser] = await ethers.getSigners();
  const mock = await ethers.deployContract('$PausableUntilMock');

  return { pauser, mock };
}

describe('Pausable', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('_pause()', function () {
    beforeEach(async function () {
      await expect(this.mock.$_pause()).to.emit(this.mock, 'Paused(address)').withArgs(this.pauser);
    });

    checkPaused(false);

    describe('unpause by function call', function () {
      beforeEach(async function () {
        await expect(this.mock.$_unpause()).to.emit(this.mock, 'Unpaused').withArgs(this.pauser);
      });

      checkUnpaused();
    });
  });

  describe('_pausedUntil(uint48)', function () {
    beforeEach(async function () {
      this.clock = await this.mock.clock();
      this.deadline = this.clock + PAUSE_DURATION;
      await expect(this.mock.$_pauseUntil(this.deadline))
        .to.emit(this.mock, 'Paused(address,uint48)')
        .withArgs(this.pauser, this.deadline);
    });

    checkPaused(true);

    describe('unpause by function call', function () {
      beforeEach(async function () {
        await expect(this.mock.$_unpause()).to.emit(this.mock, 'Unpaused').withArgs(this.pauser);
      });

      checkUnpaused();
    });

    describe('unpause by time passing', function () {
      beforeEach(async function () {
        await time.increaseTo.timestamp(this.deadline);
      });

      checkUnpaused(false);

      describe('paused after pause duration passed', function () {
        beforeEach(async function () {
          await expect(this.mock.$_pause()).to.emit(this.mock, 'Paused(address)').withArgs(this.pauser);
        });

        checkPaused(false);
      });

      describe('pausedUntil after pause duration passed', function () {
        beforeEach(async function () {
          this.clock = await this.mock.clock();
          this.deadline = this.clock + PAUSE_DURATION;
          await expect(this.mock.$_pauseUntil(this.deadline))
            .to.emit(this.mock, 'Paused(address,uint48)')
            .withArgs(this.pauser, this.deadline);
        });

        checkPaused(true);
      });
    });
  });
});
