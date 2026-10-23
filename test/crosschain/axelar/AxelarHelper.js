export async function deploy(connection, owner) {
  const axelar = await connection.ethers.deployContract('AxelarGatewayMock');
  const gatewayA = await connection.ethers.deployContract('AxelarGatewayAdapter', [axelar, owner]);
  const gatewayB = await connection.ethers.deployContract('AxelarGatewayAdapter', [axelar, owner]);

  await Promise.all([
    gatewayA.connect(owner).registerChainEquivalence(connection.helpers.chain.erc7930, 'local'),
    gatewayB.connect(owner).registerChainEquivalence(connection.helpers.chain.erc7930, 'local'),
    gatewayA.connect(owner).registerRemoteGateway(connection.helpers.chain.toErc7930(gatewayB)),
    gatewayB.connect(owner).registerRemoteGateway(connection.helpers.chain.toErc7930(gatewayA)),
  ]);

  return { axelar, gatewayA, gatewayB };
}
