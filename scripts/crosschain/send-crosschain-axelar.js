const { ethers } = require('ethers');
require('dotenv').config();

const gatewayAddresses = {
  sepolia: {
    chainId: 11155111,
    gateway: '0xe432150cce91c13a887f7D836923d5597adD8E31',
    axelarId: 'ethereum-sepolia',
    rpcUrl: process.env.SEPOLIA_RPC_URL,
  },

  arbitrumSepolia: {
    chainId: 421614,
    gateway: '0xe1cE95479C84e9809269227C7F8524aE051Ae77a',
    gasService: '0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6',
    axelarId: 'arbitrum-sepolia',
    rpcUrl: process.env.ARBITRUM_SEPOLIA_RPC_URL,
  },
  optimismSepolia: {
    chainId: 11155420,
    gateway: '0xe432150cce91c13a887f7D836923d5597adD8E31',
    axelarId: 'optimism-sepolia',
    gasService: '0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6',
    rpcUrl: process.env.OPTIMISM_SEPOLIA_RPC_URL,
  },
  baseSepolia: {
    chainId: 84532,
    gateway: '0xe432150cce91c13a887f7D836923d5597adD8E31',
    gasService: '0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6',
    axelarId: 'base-sepolia',
    rpcUrl: process.env.BASE_SEPOLIA_RPC_URL,
  },
};

const getAddress = account => ethers.getAddress(account.target ?? account.address ?? account);

function getContract(name, path) {
  // get the file in .json format
  const contractArtifact = require(`../../artifacts/contracts/${path}/${name}.sol/${name}.json`);
  return contractArtifact;
}

async function deployAxelarGatewayDuplex(chain) {
  const provider = new ethers.JsonRpcProvider(chain.rpcUrl);
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  const owner = getAddress(wallet);
  const duplexContractArtifact = getContract('AxelarGatewayDuplex', 'crosschain/axelar');
  const factory = new ethers.ContractFactory(duplexContractArtifact.abi, duplexContractArtifact.bytecode, wallet);
  const gateway = await factory.deploy(chain.gateway, owner);
  return getAddress(gateway);
}

async function deployERC7786Receiver(chain, gatewayAddress) {
  const provider = new ethers.JsonRpcProvider(chain.rpcUrl);
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  const erc7786ReceiverArtifact = getContract('ERC7786ReceiverMock', 'mocks/crosschain');
  const factory = new ethers.ContractFactory(erc7786ReceiverArtifact.abi, erc7786ReceiverArtifact.bytecode, wallet);
  const receiver = await factory.deploy(gatewayAddress);
  return getAddress(receiver);
}

async function registerRemoteGateway(originGatewayAddress, originChain, targetGatewayAddress, targetChain) {
  const provider = new ethers.JsonRpcProvider(originChain.rpcUrl);
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  const duplexContractArtifact = getContract('AxelarGatewayDuplex', 'crosschain/axelar');

  const srcGateway = new ethers.Contract(originGatewayAddress, duplexContractArtifact.abi, wallet);

  const CAIP2Target = `eip155:${targetChain.chainId}`;

  const txChainEquivalence = await srcGateway.registerChainEquivalence(CAIP2Target, targetChain.axelarId);
  await txChainEquivalence.wait();

  const txRegisterRemote = await srcGateway.registerRemoteGateway(CAIP2Target, targetGatewayAddress);
  await txRegisterRemote.wait();
}

async function sendMessage(srcGatewayAddress, srcChain, receiverAddress, dstChain, payload, attributes) {
  const provider = new ethers.JsonRpcProvider(srcChain.rpcUrl);
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  const duplexContractArtifact = getContract('AxelarGatewayDuplex', 'crosschain/axelar');

  const srcGateway = new ethers.Contract(srcGatewayAddress, duplexContractArtifact.abi, wallet);
  const CAIP2Target = `eip155:${dstChain.chainId}`;

  await srcGateway.sendMessage(CAIP2Target, receiverAddress, payload, attributes);
}

async function main() {
  const srcChain = gatewayAddresses.baseSepolia;
  const dstChain = gatewayAddresses.arbitrumSepolia;

  const srcGateway = await deployAxelarGatewayDuplex(srcChain);
  console.log('Deployed srcGateway on chain ', srcChain.chainId, ' at address ', srcGateway);

  const dstGateway = await deployAxelarGatewayDuplex(dstChain);
  console.log('Deployed dstGateway on chain ', dstChain.chainId, ' at address ', dstGateway);

  const erc7786Receiver = await deployERC7786Receiver(dstChain, dstGateway);
  console.log('Deployed erc7786Receiver on chain ', dstChain.chainId, ' at address ', erc7786Receiver);

  await registerRemoteGateway(srcGateway, srcChain, dstGateway, dstChain);
  console.log('Registered remote gateway on chain ', srcChain.chainId, ' to ', dstGateway);
  await registerRemoteGateway(dstGateway, dstChain, srcGateway, srcChain);
  console.log('Registered remote gateway on chain ', dstChain.chainId, ' to ', srcGateway);

  console.log('Sending message from chain ', srcChain.chainId, ' to chain ', dstChain.chainId);

  const payload = ethers.randomBytes(10);
  const attributes = [];

  await sendMessage(srcGateway, srcChain, erc7786Receiver, dstChain, payload, attributes);

  console.log('Sent message from chain ', srcChain.chainId, ' to chain ', dstChain.chainId);
}

main();
