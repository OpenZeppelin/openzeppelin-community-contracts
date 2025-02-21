const { ethers } = require('hardhat');

async function deploy(owner, CAIP2 = undefined) {
  CAIP2 ??= await ethers.provider.getNetwork().then(({ chainId }) => `eip155:${chainId}`);

  const axelar = await ethers.deployContract('AxelarGatewayMock');

  const gatewayA = await ethers.deployContract('AxelarGatewayDuplex', [axelar, owner]);
  const gatewayB = await ethers.deployContract('AxelarGatewayDuplex', [axelar, owner]);

  await Promise.all([
    gatewayA.connect(owner).registerChainEquivalence(CAIP2, 'local'),
    gatewayB.connect(owner).registerChainEquivalence(CAIP2, 'local'),
    gatewayA.connect(owner).registerRemoteGateway(CAIP2, gatewayB.target),
    gatewayB.connect(owner).registerRemoteGateway(CAIP2, gatewayA.target),
  ]);

  return { CAIP2, axelar, gatewayA, gatewayB };
}

module.exports = {
  deploy,
};
