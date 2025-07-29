const { ethers } = require('hardhat');
const { getLocalChain } = require('@openzeppelin/contracts/test/helpers/chains');

async function deploy(owner) {
  const chain = await getLocalChain();

  const axelar = await Promise.all([
    ethers.deployContract('AxelarGatewayMock'),
    ethers.deployContract('AxelarGasServiceMock'),
  ]).then(([gateway, gasService]) => ({ gateway, gasService }));

  const gatewayA = await ethers.deployContract('AxelarGatewayAdaptor', [axelar.gateway, axelar.gasService, owner]);
  const gatewayB = await ethers.deployContract('AxelarGatewayAdaptor', [axelar.gateway, axelar.gasService, owner]);

  await Promise.all([
    gatewayA.connect(owner).registerChainEquivalence(chain.erc7930, 'local'),
    gatewayB.connect(owner).registerChainEquivalence(chain.erc7930, 'local'),
    gatewayA.connect(owner).registerRemoteGateway(chain.toErc7930(gatewayB)),
    gatewayB.connect(owner).registerRemoteGateway(chain.toErc7930(gatewayA)),
  ]);

  return { chain, axelar, gatewayA, gatewayB };
}

module.exports = {
  deploy,
};
