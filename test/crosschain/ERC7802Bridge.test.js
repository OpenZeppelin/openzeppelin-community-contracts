const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const AxelarHelper = require('./axelar/AxelarHelper');

async function fixture() {
  const [owner, ...accounts] = await ethers.getSigners();

  const { chain, gatewayA, gatewayB } = await AxelarHelper.deploy(owner);

  // On chain A, we have a "legacy" token, and a custodian bridge
  const tokenA = await ethers.deployContract('$ERC20', ['Token A', 'TA']);
  const bridgeA = await ethers.deployContract('$ERC7802BridgeCustody', [owner]);

  // On chain B we have a simple bridge, with a bridgeable token
  const bridgeB = await ethers.deployContract('$ERC7802Bridge', [owner]);
  const tokenB = await ethers.deployContract('$ERC20BridgeableMock', ['Token B', 'TB', bridgeB]);

  await Promise.all([
    bridgeA.connect(owner).registerGateway(gatewayA, chain.erc7930),
    bridgeB.connect(owner).registerGateway(gatewayB, chain.erc7930),
    bridgeA.connect(owner).registerRemote(tokenA, chain.toErc7930(bridgeB), chain.toErc7930(tokenB)),
    bridgeB.connect(owner).registerRemote(tokenB, chain.toErc7930(bridgeA), chain.toErc7930(tokenA)),
  ]);

  return { owner, accounts, chain, gatewayA, gatewayB, bridgeA, bridgeB, tokenA, tokenB };
}

describe('ERC7802Bridge', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('initial setup', async function () {
    await expect(this.bridgeA.getGateway(this.chain.erc7930)).to.eventually.equal(this.gatewayA);
    await expect(this.bridgeA.getRemoteBridge(this.tokenA, this.chain.erc7930)).to.eventually.equal(
      this.chain.toErc7930(this.bridgeB),
    );
    await expect(this.bridgeA.getRemoteToken(this.tokenA, this.chain.erc7930)).to.eventually.equal(
      this.chain.toErc7930(this.tokenB),
    );

    await expect(this.bridgeB.getGateway(this.chain.erc7930)).to.eventually.equal(this.gatewayB);
    await expect(this.bridgeB.getRemoteBridge(this.tokenB, this.chain.erc7930)).to.eventually.equal(
      this.chain.toErc7930(this.bridgeA),
    );
    await expect(this.bridgeB.getRemoteToken(this.tokenB, this.chain.erc7930)).to.eventually.equal(
      this.chain.toErc7930(this.tokenA),
    );
  });

  it('crosschain send', async function () {
    const [alice, bruce, chris] = this.accounts;
    const amount = 100n;

    await this.tokenA.$_mint(alice, amount);
    await this.tokenA.connect(alice).approve(this.bridgeA, ethers.MaxUint256);

    await expect(this.tokenA.balanceOf(this.bridgeA)).to.eventually.equal(0n);
    await expect(this.tokenB.balanceOf(this.bridgeB)).to.eventually.equal(0n);

    // Alice sends tokens from chain A to Bruce on chain B. The 7802 custodian bridge on chain A takes ownership of Alice's tokens.
    await expect(this.bridgeA.connect(alice).send(this.tokenA, this.chain.toErc7930(bruce), amount, []))
      .to.emit(this.tokenA, 'Transfer')
      .withArgs(alice, this.bridgeA, amount) // bridge A takes custody of the funds
      .to.emit(this.bridgeA, 'Sent')
      .withArgs(this.tokenA, alice, this.chain.toErc7930(bruce), amount)
      .to.emit(this.gatewayA, 'MessageSent')
      .to.emit(this.bridgeB, 'Received')
      .withArgs(this.tokenB, this.chain.toErc7930(alice), bruce, amount)
      .to.emit(this.tokenB, 'Transfer')
      .withArgs(ethers.ZeroAddress, bruce, amount);

    await expect(this.tokenA.balanceOf(this.bridgeA)).to.eventually.equal(amount); // custody
    await expect(this.tokenB.balanceOf(this.bridgeB)).to.eventually.equal(0n);

    // Bruce sends tokens from chain B to Chris on chain B. The 7802 custodian bridge on chain A releases ownership of the tokens to Chris.
    await expect(this.bridgeB.connect(bruce).send(this.tokenB, this.chain.toErc7930(chris), amount, []))
      .to.emit(this.tokenB, 'Transfer')
      .withArgs(bruce, ethers.ZeroAddress, amount) // bridge B burns the tokens
      .to.emit(this.bridgeB, 'Sent')
      .withArgs(this.tokenB, bruce, this.chain.toErc7930(chris), amount)
      .to.emit(this.gatewayB, 'MessageSent')
      .to.emit(this.bridgeA, 'Received')
      .withArgs(this.tokenA, this.chain.toErc7930(bruce), chris, amount)
      .to.emit(this.tokenA, 'Transfer')
      .withArgs(this.bridgeA, chris, amount);

    await expect(this.tokenA.balanceOf(this.bridgeA)).to.eventually.equal(0n);
    await expect(this.tokenB.balanceOf(this.bridgeB)).to.eventually.equal(0n);
  });
});
