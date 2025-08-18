const { ethers } = require('hardhat');
const { getLocalChain } = require('@openzeppelin/contracts/test/helpers/chains');

async function deploy(owner) {
  const chain = await getLocalChain();

  const axelar = await ethers.deployContract('AxelarGatewayMock');
  const gatewayA = await ethers.deployContract('AxelarGatewayAdapter', [axelar, owner]);
  const gatewayB = await ethers.deployContract('AxelarGatewayAdapter', [axelar, owner]);

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
