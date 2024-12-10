const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { shouldBehaveLikeERC20 } = require('../../../../lib/@openzeppelin-contracts/test/token/ERC20/ERC20.behavior');
const {
  shouldSupportInterfaces,
} = require('../../../../lib/@openzeppelin-contracts/test/utils/introspection/SupportsInterface.behavior');

const name = 'My Token';
const symbol = 'MTKN';
const initialSupply = 100n;

async function fixture() {
  const [other, bridge, ...accounts] = await ethers.getSigners();

  const token = await ethers.deployContract('$ERC20BridgeableMock', [name, symbol, bridge]);
  await token.$_mint(accounts[0].address, initialSupply);

  return { bridge, other, accounts, token };
}

describe('ERC20Bridgeable', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('onlyTokenBridgeFn', function () {
    it('reverts when called by non-bridge', async function () {
      await expect(this.token.onlyTokenBridgeFn()).to.be.revertedWithCustomError(this.token, 'OnlyTokenBridge');
    });

    it('does not revert when called by bridge', async function () {
      await expect(this.token.connect(this.bridge).onlyTokenBridgeFn())
        .to.emit(this.token, 'OnlyTokenBridgeFnCalled')
        .withArgs(this.bridge);
    });
  });

  describe('crosschainMint', function () {
    it('reverts when called by non-bridge', async function () {
      await expect(this.token.crosschainMint(this.other.address, 100n)).to.be.revertedWithCustomError(
        this.token,
        'OnlyTokenBridge',
      );
    });

    it('mints amount provided by the bridge when calling crosschainMint', async function () {
      const amount = 100n;
      await expect(this.token.connect(this.bridge).crosschainMint(this.other.address, amount))
        .to.emit(this.token, 'CrosschainMint')
        .withArgs(this.other.address, amount, this.bridge.address)
        .to.emit(this.token, 'Transfer')
        .withArgs(ethers.ZeroAddress, this.other.address, amount);

      expect(await this.token.balanceOf(this.other.address)).to.equal(amount);
    });
  });

  describe('crosschainBurn', function () {
    it('reverts when called by non-bridge', async function () {
      await expect(this.token.crosschainBurn(this.other.address, 100n)).to.be.revertedWithCustomError(
        this.token,
        'OnlyTokenBridge',
      );
    });

    it('burns amount provided by the bridge when calling crosschainBurn', async function () {
      const amount = 100n;
      await this.token.$_mint(this.other.address, amount);

      await expect(this.token.connect(this.bridge).crosschainBurn(this.other.address, amount))
        .to.emit(this.token, 'CrosschainBurn')
        .withArgs(this.other.address, amount, this.bridge.address)
        .to.emit(this.token, 'Transfer')
        .withArgs(this.other.address, ethers.ZeroAddress, amount);

      expect(await this.token.balanceOf(this.other.address)).to.equal(0);
    });
  });

  describe('ERC165', function () {
    shouldSupportInterfaces(['ERC7802'], {
      ERC7802: ['crosschainMint(address,uint256)', 'crosschainBurn(address,uint256)'],
    });
  });

  describe('ERC20 behavior', function () {
    shouldBehaveLikeERC20(initialSupply);
  });
});
