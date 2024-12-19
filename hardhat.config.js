const { argv } = require('yargs/yargs')()
  .env('')
  .options({
    compiler: {
      type: 'string',
      default: '0.8.27',
    },
    hardfork: {
      type: 'string',
      default: 'cancun',
    },
  });

require('@nomicfoundation/hardhat-chai-matchers');
require('@nomicfoundation/hardhat-ethers');
require('hardhat-exposed');
require('solidity-coverage');
require('solidity-docgen');
require('./hardhat/remappings');
require('@openzeppelin/contracts/hardhat/common-contracts');

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
  docgen: require('./docs/config'),
};
