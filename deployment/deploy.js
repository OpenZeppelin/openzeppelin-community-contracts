const { ethers } = require('hardhat');
const yargs = require('yargs/yargs');
const { hideBin } = require('yargs/helpers');

const MigrationManager = require('./helpers/MigrationManager');
const config = require('./config');
const argv = yargs(hideBin(process.argv)).env('').argv;

const toUniversalAddress = addr => ethers.zeroPadValue(addr.target ?? addr.address ?? addr, 32);

function makeChain(config, { mnemonic, pk }) {
  const chain = {};
  chain.provider = ethers.getDefaultProvider(config.url);
  chain.signer = (pk ? new ethers.Wallet(pk) : ethers.Wallet.fromPhrase(mnemonic)).connect(chain.provider);
  chain.manager = new MigrationManager(chain.provider);
  chain.config = config;
  chain.getFactory = name => ethers.getContractFactory(name).then(contract => contract.connect(chain.signer));
  return chain;
}

(async () => {
  const opts = {};

  const chain1 = makeChain(config.arbitrumSepolia, argv);
  const chain2 = makeChain(config.baseSepolia, argv);
  chain1.caip2 = await chain1.provider.getNetwork().then(({ chainId }) => `eip155:${chainId}`);
  chain2.caip2 = await chain2.provider.getNetwork().then(({ chainId }) => `eip155:${chainId}`);

  console.log('> chain details');
  console.log(`[${chain1.caip2}] ${chain1.signer.address} ${chain1.config.url}`);
  console.log(`[${chain2.caip2}] ${chain2.signer.address} ${chain2.config.url}`);
  console.log();

  /// SETUP AXELAR
  process.stdout.write("> deploy axelar gateways ... ");
  const axelar1 = await chain1.manager.migrate('axelar', chain1.getFactory('AxelarGatewayDuplex'), [ chain1.config.axelar.gateway, chain1.signer.address ], opts);
  const axelar2 = await chain2.manager.migrate('axelar', chain2.getFactory('AxelarGatewayDuplex'), [ chain2.config.axelar.gateway, chain2.signer.address ], opts);
  process.stdout.write("done\n");

  process.stdout.write("> configure axelar gateways ... ");
  await axelar1.getEquivalentChain(chain2.caip2).catch(() => axelar1.registerChainEquivalence(chain2.caip2, chain2.config.axelar.id).then(tx => tx.wait()));
  await axelar2.getEquivalentChain(chain1.caip2).catch(() => axelar2.registerChainEquivalence(chain1.caip2, chain1.config.axelar.id).then(tx => tx.wait()));
  await axelar1.getRemoteGateway(chain2.caip2).catch(() => axelar1.registerRemoteGateway(chain2.caip2, axelar2.target).then(tx => tx.wait()));
  await axelar2.getRemoteGateway(chain1.caip2).catch(() => axelar2.registerRemoteGateway(chain1.caip2, axelar1.target).then(tx => tx.wait()));
  process.stdout.write("done\n");

  /// SETUP WORMHOLE
  process.stdout.write('> deploy wormhole gateways ... ');
  const wormhole1 = await chain1.manager.migrate('wormhole', chain1.getFactory('WormholeGatewayDuplex'), [chain1.config.wormhole.relayer, chain1.config.wormhole.id, chain1.signer.address], opts);
  const wormhole2 = await chain2.manager.migrate('wormhole', chain2.getFactory('WormholeGatewayDuplex'), [chain2.config.wormhole.relayer, chain2.config.wormhole.id, chain2.signer.address], opts);
  process.stdout.write('done\n');

  process.stdout.write('> configure wormhole gateways ... ');
  await wormhole1.fromCAIP2(chain2.caip2).catch(() => wormhole1.registerChainEquivalence(chain2.caip2, chain2.config.wormhole.id).then(tx => tx.wait()));
  await wormhole2.fromCAIP2(chain1.caip2).catch(() => wormhole2.registerChainEquivalence(chain1.caip2, chain1.config.wormhole.id).then(tx => tx.wait()));
  await wormhole1.getRemoteGateway(chain2.caip2).catch(() => wormhole1.registerRemoteGateway(chain2.caip2, toUniversalAddress(wormhole2.target)).then(tx => tx.wait()));
  await wormhole2.getRemoteGateway(chain1.caip2).catch(() => wormhole2.registerRemoteGateway(chain1.caip2, toUniversalAddress(wormhole1.target)).then(tx => tx.wait()));
  process.stdout.write('done\n');

  // RECEIVER
  // const receiver = await chain2.manager.migrate('axelar-receiver', chain2.getFactory('ERC7786ReceiverMock'), [axelar2.target], opts);
  // const receiver = await chain2.manager.migrate('wormhole-receiver', chain2.getFactory('ERC7786ReceiverMock'), [wormhole2.target], opts);
})();
