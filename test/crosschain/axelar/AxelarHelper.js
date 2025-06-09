const { ethers } = require('hardhat');
const { getLocalChain } = require('../../helpers/chains');

async function deploy(owner) {
  const chain = await getLocalChain();

  const axelar = await ethers.deployContract('AxelarGatewayMock');
  const gatewayA = await ethers.deployContract('AxelarGatewayDuplex', [axelar, owner]);
  const gatewayB = await ethers.deployContract('AxelarGatewayDuplex', [axelar, owner]);

  await Promise.all([
    gatewayA.connect(owner).registerChainEquivalence(chain.erc7930.binary, 'local'),
    gatewayB.connect(owner).registerChainEquivalence(chain.erc7930.binary, 'local'),
    gatewayA.connect(owner).registerRemoteGateway(chain.toErc7930(gatewayB).binary),
    gatewayB.connect(owner).registerRemoteGateway(chain.toErc7930(gatewayA).binary),
  ]);

  return { chain, axelar, gatewayA, gatewayB };
}

module.exports = {
  deploy,
};
