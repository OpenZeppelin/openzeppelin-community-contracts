// - COMPILER:      compiler version (default: 0.8.27)
// - HARDFORK:      hardfork version (default: prague)
// - GAS:           enable gas report (default: false)
// - COINMARKETCAP: coinmarketcap api key for USD value in gas report

const { argv } = require('yargs/yargs')()
  .env('')
  .options({
    compiler: {
      type: 'string',
      default: '0.8.27',
    },
    hardfork: {
      type: 'string',
      default: 'prague',
    },
    gas: {
      alias: 'enableGasReport',
      type: 'boolean',
      default: false,
    },
    coinmarketcap: {
      alias: 'coinmarketcap',
      type: 'string',
      default: '',
    },
  });

require('@nomicfoundation/hardhat-chai-matchers');
require('@nomicfoundation/hardhat-ethers');
require('hardhat-exposed');
require('hardhat-gas-reporter');
require('hardhat-predeploy');
require('solidity-coverage');
require('solidity-docgen');
require('./hardhat/remappings');

module.exports = {
  solidity: {
    version: argv.compiler,
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: argv.hardfork,
    },
  },
  networks: {
    hardhat: {
      hardfork: argv.hardfork,
    },
  },
  exposed: {
    imports: true,
    initializers: true,
  },
  gasReporter: {
    enabled: argv.gas,
    showMethodSig: true,
    includeBytecodeInJSON: true,
    currency: 'USD',
    coinmarketcap: argv.coinmarketcap,
  },
  docgen: require('./docs/config'),
};
