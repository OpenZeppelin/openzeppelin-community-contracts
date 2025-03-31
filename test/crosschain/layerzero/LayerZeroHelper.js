const { ethers } = require('hardhat');

const toUniversalAddress = addr => ethers.zeroPadValue(addr.target ?? addr.address ?? addr, 32);
const fromUniversalAddress = addr => ethers.getAddress(ethers.hexlify(ethers.getBytes(addr).slice(-20)));

async function deploy(owner, CAIP2 = undefined, layerZeroChainId = 23600) {
  CAIP2 ??= await ethers.provider.getNetwork().then(({ chainId }) => `eip155:${chainId}`);

  const layerZero = await ethers.deployContract('LayerZeroEndpointMock');

  const gatewayA = await ethers.deployContract('LayerZeroGatewayDuplex', [layerZero, owner]);
  const gatewayB = await ethers.deployContract('LayerZeroGatewayDuplex', [layerZero, owner]);

  await Promise.all([
    gatewayA.connect(owner).registerChainEquivalence(CAIP2, layerZeroChainId),
    gatewayB.connect(owner).registerChainEquivalence(CAIP2, layerZeroChainId),
    gatewayA.connect(owner).registerRemoteGateway(CAIP2, toUniversalAddress(gatewayB)),
    gatewayB.connect(owner).registerRemoteGateway(CAIP2, toUniversalAddress(gatewayA)),
  ]);

  return { CAIP2, layerZeroChainId, layerZero, gatewayA, gatewayB };
}

module.exports = {
  deploy,
  toUniversalAddress,
  fromUniversalAddress,
};
