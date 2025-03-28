module.exports = {
  arbitrumSepolia: {
    // url: process.env.ARBITRUM_SEPOLIA_RPC_URL ?? 'https://api.zan.top/arb-sepolia',
    // url: process.env.ARBITRUM_SEPOLIA_RPC_URL ?? 'https://arbitrum-sepolia.gateway.tenderly.co',
    url: process.env.ARBITRUM_SEPOLIA_RPC_URL ?? 'https://arbitrum-sepolia-rpc.publicnode.com',
    axelar: {
      id: 'arbitrum-sepolia',
      gateway: '0xe1cE95479C84e9809269227C7F8524aE051Ae77a',
      gasService: '0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6',
    },
    wormhole: {
      id: '10003',
      relayer: '0x7B1bD7a6b4E61c2a123AC6BC2cbfC614437D0470',
    },
  },
  baseSepolia: {
    // url: process.env.BASE_SEPOLIA_RPC_URL ?? 'https://base-sepolia.drpc.org',
    url: process.env.BASE_SEPOLIA_RPC_URL ?? 'https://sepolia.base.org',
    axelar: {
      id: 'base-sepolia',
      gateway: '0xe432150cce91c13a887f7D836923d5597adD8E31',
      gasService: '0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6',
    },
    wormhole: {
      id: '10004',
      relayer: '0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE',
    },
  },
  optimismSepolia: {
    url: process.env.OPTIMISM_SEPOLIA_RPC_URL,
    axelar: {
      id: 'optimism-sepolia',
      gateway: '0xe432150cce91c13a887f7D836923d5597adD8E31',
      gasService: '0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6',
    },
    wormhole: {
      id: '10005',
      relayer: '0x93BAD53DDfB6132b0aC8E37f6029163E63372cEE',
    },
  },
};
