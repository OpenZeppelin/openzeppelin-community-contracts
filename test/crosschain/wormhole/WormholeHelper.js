const { ethers } = require('hardhat');

const toUniversalAddress = addr => ethers.zeroPadValue(addr.target ?? addr.address ?? addr, 32);
const fromUniversalAddress = addr => ethers.getAddress(ethers.hexlify(ethers.getBytes(addr).slice(-20)));

async function deploy(owner, CAIP2 = undefined, wormholeChainId = 23600) {
  CAIP2 ??= await ethers.provider.getNetwork().then(({ chainId }) => `eip155:${chainId}`);

  const wormhole = await ethers.deployContract('WormholeRelayerMock');

  const gatewayA = await ethers.deployContract('WormholeGatewayDuplex', [wormhole, wormholeChainId, owner]);
  const gatewayB = await ethers.deployContract('WormholeGatewayDuplex', [wormhole, wormholeChainId, owner]);

  await Promise.all([
    gatewayA.connect(owner).registerChainEquivalence(CAIP2, wormholeChainId),
    gatewayB.connect(owner).registerChainEquivalence(CAIP2, wormholeChainId),
    gatewayA.connect(owner).registerRemoteGateway(CAIP2, toUniversalAddress(gatewayB)),
    gatewayB.connect(owner).registerRemoteGateway(CAIP2, toUniversalAddress(gatewayA)),
  ]);

  return { CAIP2, wormholeChainId, wormhole, gatewayA, gatewayB };
}

module.exports = {
  deploy,
  toUniversalAddress,
  fromUniversalAddress,
};
