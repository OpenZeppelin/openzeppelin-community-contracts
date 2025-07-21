const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const AxelarHelper = require('./axelar/AxelarHelper');

const keccak256AbiEncode = (types, values) => ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(types, values));
const sortBytes32 = values => values.sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));

async function fixture() {
  const [admin, ...accounts] = await ethers.getSigners();

  const { chain, gatewayA, gatewayB } = await AxelarHelper.deploy(admin);

  // On chain A, we have a "legacy" token
  const bridgeA = await ethers.deployContract('$ERC7802Bridge');
  const tokenA = await ethers.deployContract('$ERC20', ['Token A', 'TA']);

  // On chain B we have a bridgeable token
  const bridgeB = await ethers.deployContract('$ERC7802Bridge');
  const tokenB = await ethers.deployContract('$ERC20BridgeableMock', ['Token B', 'TB', admin]);

  // Bridge side identifiers
  const chainAId = keccak256AbiEncode(
    ['bytes', 'bytes32', 'bytes32[]'],
    [
      chain.toErc7930(tokenA),
      '0x0000000000000000000000000000000000000000000000000000000000000001', // custodial
      sortBytes32([keccak256AbiEncode(['bytes', 'bytes'], [chain.toErc7930(gatewayA), chain.toErc7930(bridgeB)])]),
    ],
  );

  const chainBId = keccak256AbiEncode(
    ['bytes', 'bytes32', 'bytes32[]'],
    [
      chain.toErc7930(tokenB),
      '0x0000000000000000000000000000000000000000000000000000000000000000', // crosschain
      sortBytes32([keccak256AbiEncode(['bytes', 'bytes'], [chain.toErc7930(gatewayB), chain.toErc7930(bridgeA)])]),
    ],
  );

  // Bridge global identifier
  const id = ethers.solidityPackedKeccak256(['bytes32[]'], [sortBytes32([chainAId, chainBId])]);

  // Register bridge
  await expect(
    bridgeA.createBridge(
      tokenA,
      true, // is custodial
      [{ id: chainBId, gateway: gatewayA, remote: chain.toErc7930(bridgeB) }], // link to B + id of B
    ),
  )
    .to.emit(bridgeA, 'NewBridge')
    .withArgs(id, tokenA);

  await expect(
    bridgeB.createBridge(
      tokenB,
      false, // is crosschain
      [{ id: chainAId, gateway: gatewayB, remote: chain.toErc7930(bridgeA) }], // link to B + id of B
    ),
  )
    .to.emit(bridgeB, 'NewBridge')
    .withArgs(id, tokenB);

  // Get endpoint for that bridge
  const endpointA = await bridgeA.getBridgeEndpoint.staticCall(id);
  const endpointB = await bridgeB.getBridgeEndpoint.staticCall(id);

  // Whitelist
  await tokenB.connect(admin).grantRole(ethers.id('BRIDGE'), endpointB);

  return { admin, accounts, chain, tokenA, tokenB, gatewayA, gatewayB, bridgeA, bridgeB, endpointA, endpointB, id };
}

describe('ERC7802Bridge', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('initial setup', async function () {
    await expect(this.bridgeA.getBridgeToken(this.id)).to.eventually.deep.equal([this.tokenA.target, true]);
    await expect(this.bridgeA.getBridgeGateway(this.id, this.chain.erc7930)).to.eventually.equal(this.gatewayA);
    await expect(this.bridgeA.getBridgeRemote(this.id, this.chain.erc7930)).to.eventually.equal(
      this.chain.toErc7930(this.bridgeB),
    );

    await expect(this.bridgeB.getBridgeToken(this.id)).to.eventually.deep.equal([this.tokenB.target, false]);
    await expect(this.bridgeB.getBridgeGateway(this.id, this.chain.erc7930)).to.eventually.equal(this.gatewayB);
    await expect(this.bridgeB.getBridgeRemote(this.id, this.chain.erc7930)).to.eventually.equal(
      this.chain.toErc7930(this.bridgeA),
    );
  });

  it('crosschain send', async function () {
    const [alice, bruce, chris] = this.accounts;
    const amount = 100n;

    await this.tokenA.$_mint(alice, amount);
    await this.tokenA.connect(alice).approve(this.endpointA, ethers.MaxUint256);

    await expect(this.tokenA.balanceOf(this.bridgeA)).to.eventually.equal(0n);
    await expect(this.tokenB.balanceOf(this.bridgeB)).to.eventually.equal(0n);
    await expect(this.tokenA.balanceOf(this.endpointA)).to.eventually.equal(0n);
    await expect(this.tokenA.balanceOf(this.endpointB)).to.eventually.equal(0n);

    // Alice sends tokens from chain A to Bruce on chain B. The 7802 custodian bridge on chain A takes ownership of Alice's tokens.
    await expect(this.bridgeA.connect(alice).send(this.id, this.chain.toErc7930(bruce), amount, []))
      .to.emit(this.tokenA, 'Transfer')
      .withArgs(alice, this.endpointA, amount) // endpoint on chain A takes custody of the funds
      .to.emit(this.bridgeA, 'Sent')
      .withArgs(this.tokenA, alice, this.chain.toErc7930(bruce), amount)
      .to.emit(this.gatewayA, 'MessageSent')
      .to.emit(this.bridgeB, 'Received')
      .withArgs(this.tokenB, this.chain.toErc7930(alice), bruce, amount)
      .to.emit(this.tokenB, 'Transfer')
      .withArgs(ethers.ZeroAddress, bruce, amount);

    await expect(this.tokenA.balanceOf(this.bridgeA)).to.eventually.equal(0n);
    await expect(this.tokenB.balanceOf(this.bridgeB)).to.eventually.equal(0n);
    await expect(this.tokenA.balanceOf(this.endpointA)).to.eventually.equal(amount); // custody
    await expect(this.tokenA.balanceOf(this.endpointB)).to.eventually.equal(0n);

    // Bruce sends tokens from chain B to Chris on chain B. The 7802 custodian bridge on chain A releases ownership of the tokens to Chris.
    await expect(this.bridgeB.connect(bruce).send(this.id, this.chain.toErc7930(chris), amount, []))
      .to.emit(this.tokenB, 'Transfer')
      .withArgs(bruce, ethers.ZeroAddress, amount) // bridge B burns the tokens
      .to.emit(this.bridgeB, 'Sent')
      .withArgs(this.tokenB, bruce, this.chain.toErc7930(chris), amount)
      .to.emit(this.gatewayB, 'MessageSent')
      .to.emit(this.bridgeA, 'Received')
      .withArgs(this.tokenA, this.chain.toErc7930(bruce), chris, amount)
      .to.emit(this.tokenA, 'Transfer')
      .withArgs(this.endpointA, chris, amount);

    await expect(this.tokenA.balanceOf(this.bridgeA)).to.eventually.equal(0n);
    await expect(this.tokenB.balanceOf(this.bridgeB)).to.eventually.equal(0n);
    await expect(this.tokenA.balanceOf(this.endpointA)).to.eventually.equal(0n);
    await expect(this.tokenA.balanceOf(this.endpointB)).to.eventually.equal(0n);
  });
});
