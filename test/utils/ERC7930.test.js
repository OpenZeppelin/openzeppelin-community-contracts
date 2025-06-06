const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

async function fixture() {
  const mock = await ethers.deployContract('$ERC7930');
  return { mock };
}

describe('ERC7390', function () {
  before(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('Example 1: Ethereum mainnet address', async function () {
    await expect(
      this.mock.$parseV1('0x00010000010114D8DA6BF26964AF9D7EED9E03E53415D37AA96045'),
    ).to.eventually.deep.equal([
      '0x0000', // eip155
      '0x01', // mainnet
      '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045', // 20 bytes of the ethereum address
    ]);

    await expect(this.mock.$formatEvmV1(1, '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045')).to.eventually.equal(
      '0x00010000010114D8DA6BF26964AF9D7EED9E03E53415D37AA96045'.toLowerCase(),
    );
  });

  it('Example 2: Solana mainnet address', async function () {
    await expect(
      this.mock.$parseV1(
        '0x000100022045296998a6f8e2a784db5d9f95e18fc23f70441a1039446801089879b08c7ef02005333498d5aea4ae009585c43f7b8c30df8e70187d4a713d134f977fc8dfe0b5',
      ),
    ).to.eventually.deep.equal([
      '0x0002', // solana
      '0x45296998a6f8e2a784db5d9f95e18fc23f70441a1039446801089879b08c7ef0', // 32 bytes of the solana genesis block
      '0x05333498d5aea4ae009585c43f7b8c30df8e70187d4a713d134f977fc8dfe0b5', // 32 bytes of the solana address
    ]);
  });

  it('Example 3: EVM address without chainid', async function () {
    await expect(this.mock.$parseV1('0x000100000014D8DA6BF26964AF9D7EED9E03E53415D37AA96045')).to.eventually.deep.equal(
      [
        '0x0000', // eip155
        '0x', // no chainid
        '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045', // 20 bytes of the ethereum address
      ],
    );
  });

  it('Example 4: Solana mainnet network, no address', async function () {
    await expect(
      this.mock.$parseV1('0x000100022045296998a6f8e2a784db5d9f95e18fc23f70441a1039446801089879b08c7ef000'),
    ).to.eventually.deep.equal([
      '0x0002', // solana
      '0x45296998a6f8e2a784db5d9f95e18fc23f70441a1039446801089879b08c7ef0', // 32 bytes of the solana genesis block
      '0x', // no address
    ]);
  });

  it('Example 5: Arbitrum One address', async function () {
    await expect(
      this.mock.$parseV1('0x0001000002A4B114D8DA6BF26964AF9D7EED9E03E53415D37AA96045'),
    ).to.eventually.deep.equal([
      '0x0000', // eip155
      '0xA4B1', // arbitrum one chainid (42161)
      '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045', // 20 bytes of the ethereum address
    ]);

    await expect(this.mock.$formatEvmV1(42161, '0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045')).to.eventually.equal(
      '0x0001000002A4B114D8DA6BF26964AF9D7EED9E03E53415D37AA96045'.toLowerCase(),
    );
  });
});
