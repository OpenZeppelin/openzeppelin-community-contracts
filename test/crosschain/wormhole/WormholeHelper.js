import { ethers } from 'ethers';

export const toUniversalAddress = addr => ethers.zeroPadValue(addr.target ?? addr.address ?? addr, 32);
export const fromUniversalAddress = addr => ethers.getAddress(ethers.hexlify(ethers.getBytes(addr).slice(-20)));

export async function deploy(connection, owner, wormholeChainId = 23600) {
  const wormhole = await connection.ethers.deployContract('WormholeRelayerMock', [wormholeChainId]);
  const gatewayA = await connection.ethers.deployContract('WormholeGatewayAdapter', [wormhole, wormholeChainId, owner]);
  const gatewayB = await connection.ethers.deployContract('WormholeGatewayAdapter', [wormhole, wormholeChainId, owner]);

  await gatewayA
    .connect(owner)
    .registerChainEquivalence(ethers.Typed.bytes(connection.helpers.chain.erc7930), wormholeChainId);
  await gatewayB
    .connect(owner)
    .registerChainEquivalence(ethers.Typed.bytes(connection.helpers.chain.erc7930), wormholeChainId);
  await gatewayA.connect(owner).registerRemoteGateway(ethers.Typed.bytes(connection.helpers.chain.toErc7930(gatewayB)));
  await gatewayB.connect(owner).registerRemoteGateway(ethers.Typed.bytes(connection.helpers.chain.toErc7930(gatewayA)));

  return { wormholeChainId, wormhole, gatewayA, gatewayB };
}
