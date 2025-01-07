const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

async function fixture() {
  const mock = await ethers.deployContract('$Masks');
  return { mock };
}

describe('Masks', function () {
  before(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('toMask', function () {
    for (let i = 0; i < 256; i++) {
      it(`sets group ${i}`, async function () {
        expect(await this.mock['$toMask(uint8)'](BigInt(i))).to.equal(1n << BigInt(i));
      });
    }

    // multiple groups
    const groups = [
      [0, 1],
      [0, 2],
      [0, 3],
      [5, 8],
      [5, 9],
      [9, 10],
      [2, 9],
      [8, 8],
      [123, 234],
      [182, 189],
      [200, 123],
      [255, 1],
    ];

    for (const [i, j] of groups) {
      it(`sets groups ${i} and ${j}`, async function () {
        expect(await this.mock['$toMask(uint8[])']([BigInt(i), BigInt(j)])).to.equal(
          (1n << BigInt(i)) | (1n << BigInt(j)),
        );
      });
    }
  });

  describe('get', function () {
    it('returns group for empty mask', async function () {
      expect(await this.mock.$get(ethers.toBeHex(0, 32), 0)).to.be.false;
    });

    it('returns group for non-empty mask', async function () {
      expect(await this.mock.$get(ethers.toBeHex(1, 32), 0)).to.be.true;
    });
  });

  describe('isEmpty', function () {
    it('returns true for empty mask', async function () {
      expect(await this.mock.$isEmpty(ethers.toBeHex(0, 32))).to.be.true;
    });

    it('returns false for non-empty mask', async function () {
      expect(await this.mock.$isEmpty(ethers.toBeHex(1, 32))).to.be.false;
    });
  });

  describe('complement', function () {
    it('returns complement of empty mask', async function () {
      expect(await this.mock.$complement(ethers.toBeHex(0, 32))).to.equal(ethers.toBeHex(2n ** 256n - 1n, 32));
    });

    it('returns complement of non-empty mask', async function () {
      expect(await this.mock.$complement(ethers.toBeHex(1, 32))).to.equal(
        '0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe',
      );
    });
  });

  describe('union', function () {
    it('returns union of two masks', async function () {
      expect(await this.mock.$union(ethers.toBeHex(1, 32), ethers.toBeHex(2, 32))).to.equal(ethers.toBeHex(3, 32));
    });

    it('returns union of two masks with common group', async function () {
      expect(await this.mock.$union(ethers.toBeHex(1, 32), ethers.toBeHex(3, 32))).to.equal(ethers.toBeHex(3, 32));
    });
  });

  describe('intersection', function () {
    it('returns intersection of two masks', async function () {
      expect(await this.mock.$intersection(ethers.toBeHex(1, 32), ethers.toBeHex(2, 32))).to.equal(
        ethers.toBeHex(0, 32),
      );
    });

    it('returns intersection of two masks with common group', async function () {
      expect(await this.mock.$intersection(ethers.toBeHex(1, 32), ethers.toBeHex(3, 32))).to.equal(
        ethers.toBeHex(1, 32),
      );
    });
  });

  describe('difference', function () {
    it('returns difference of two masks', async function () {
      expect(await this.mock.$difference(ethers.toBeHex(1, 32), ethers.toBeHex(2, 32))).to.equal(ethers.toBeHex(1, 32));
    });

    it('returns difference of two masks with common group', async function () {
      expect(await this.mock.$difference(ethers.toBeHex(1, 32), ethers.toBeHex(3, 32))).to.equal(ethers.toBeHex(0, 32));
    });
  });

  describe('symmetricDifference', function () {
    it('returns symmetric difference of two masks', async function () {
      expect(await this.mock.$symmetricDifference(ethers.toBeHex(1, 32), ethers.toBeHex(2, 32))).to.equal(
        ethers.toBeHex(3, 32),
      );
    });

    it('returns symmetric difference of two masks with common group', async function () {
      expect(await this.mock.$symmetricDifference(ethers.toBeHex(1, 32), ethers.toBeHex(3, 32))).to.equal(
        ethers.toBeHex(2, 32),
      );
    });
  });
});
