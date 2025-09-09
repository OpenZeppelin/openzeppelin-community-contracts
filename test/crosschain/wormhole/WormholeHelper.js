const { ethers } = require('hardhat');
const { getLocalChain } = require('@openzeppelin/contracts/test/helpers/chains');

const toUniversalAddress = addr => ethers.zeroPadValue(addr.target ?? addr.address ?? addr, 32);
const fromUniversalAddress = addr => ethers.getAddress(ethers.hexlify(ethers.getBytes(addr).slice(-20)));

async function deploy(owner, wormholeChainId = 23600) {
  const chain = await getLocalChain();

  const wormhole = await ethers.deployContract('WormholeRelayerMock', [wormholeChainId]);
  const gatewayA = await ethers.deployContract('WormholeGatewayAdapter', [wormhole, wormholeChainId, owner]);
  const gatewayB = await ethers.deployContract('WormholeGatewayAdapter', [wormhole, wormholeChainId, owner]);

  await gatewayA.connect(owner).registerChainEquivalence(ethers.Typed.bytes(chain.erc7930), wormholeChainId);
  await gatewayB.connect(owner).registerChainEquivalence(ethers.Typed.bytes(chain.erc7930), wormholeChainId);
  await gatewayA.connect(owner).registerRemoteGateway(ethers.Typed.bytes(chain.toErc7930(gatewayB)));
  await gatewayB.connect(owner).registerRemoteGateway(ethers.Typed.bytes(chain.toErc7930(gatewayA)));

  return { chain, wormholeChainId, wormhole, gatewayA, gatewayB };
}

module.exports = {
  deploy,
  toUniversalAddress,
  fromUniversalAddress,
};
