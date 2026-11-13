import { defineConfig } from 'hardhat/config';

// Plugins
import hardhatEthers from '@nomicfoundation/hardhat-ethers';
import hardhatEthersChaiMatchers from '@nomicfoundation/hardhat-ethers-chai-matchers';
import hardhatIgnoreWarnings from 'hardhat-ignore-warnings';
import hardhatMocha from '@nomicfoundation/hardhat-mocha';
import hardhatNetworkHelpers from '@nomicfoundation/hardhat-network-helpers';
import hardhatPredeploy from 'hardhat-predeploy';
import hardhatDocgen from '@openzeppelin/contracts/hardhat/hardhat-solidity-docgen/plugin.ts';
import hardhatExposed from '@openzeppelin/contracts/hardhat/hardhat-exposed/plugin.ts';
import hardhatTranspiler from '@openzeppelin/contracts/hardhat/hardhat-transpiler/plugin.ts';
import hardhatOzContractsHelpers from '@openzeppelin/contracts/hardhat/hardhat-oz-contracts-helpers/plugin.ts';
import '@openzeppelin/contracts/hardhat/async-test-sanity.ts';
import hardhatRemappingsPlugin from './hardhat/hardhat-remappings.ts';

// Parameters
import yargs from 'yargs/yargs';
const argv = await yargs()
  .env('')
  .options({
    compiler: { type: 'string', default: '0.8.35' },
    src: { type: 'string', default: 'contracts' },
    runs: { type: 'number', default: 200 },
    ir: { type: 'boolean', default: false },
    evm: { type: 'string', default: 'osaka' },
  })
  .parse();

// `remappings.txt` points `@openzeppelin/contracts` to the submodule, which is what Foundry (and projects that install
// this repository with `forge install`) need. Hardhat must instead resolve it through `node_modules`, as an npm
// package, for `npmFilesToBuild` to accept its files and for every dependency to share a single copy (the
// `zk-email-verify` submodule resolves `@openzeppelin/contracts` through npm). These remappings take precedence over
// the ones of `remappings.txt` for Hardhat only.
const hardhatRemappings = [
  '@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/contracts/',
  'lib/@openzeppelin-contracts-upgradeable/contracts/:@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/contracts/',
];

// Configuration
export default defineConfig({
  plugins: [
    // Imported plugins
    hardhatEthers,
    hardhatEthersChaiMatchers,
    hardhatIgnoreWarnings,
    hardhatMocha,
    hardhatNetworkHelpers,
    hardhatPredeploy,
    // Local plugins
    hardhatDocgen,
    hardhatExposed,
    hardhatTranspiler,
    hardhatOzContractsHelpers,
    hardhatRemappingsPlugin(hardhatRemappings),
  ],
  paths: {
    // `ECDSAOwnedDKIMRegistry` is needed (as-is, not exposed) by the tests. It lives in a submodule reached through a
    // remappings.txt entry, so it is a project file that no compilation root imports by name: `npmFilesToBuild` cannot
    // reach it (HHE901), and being imported is not enough for Hardhat 3 to emit an artifact. Building its directory as
    // a source directory is what makes those artifacts appear.
    sources: [argv.src, 'lib/email-tx-builder/packages/contracts/src/utils'],
  },
  solidity: {
    version: argv.compiler,
    // Remappings are defined in `remappings.txt`, and overridden for Hardhat by `hardhatRemappings` (see above).
    // Hardhat 3 also applies the `remappings.txt` of the `lib/@openzeppelin-contracts-upgradeable` submodule to its
    // files, which points `@openzeppelin/contracts` to a nested copy. The last entry of `remappings.txt` (and of
    // `hardhatRemappings`) uses a more specific context so that the submodule uses the same copy as the rest of the
    // project. (Comments are not allowed in `remappings.txt` as Foundry rejects them.)
    //
    // Dependencies that the tests deploy directly. Hardhat 3 only emits artifacts for compilation roots, so importing
    // them from a solidity file (the old `contracts/mocks/import.sol` trick) is not enough anymore.
    npmFilesToBuild: [
      '@openzeppelin/contracts/mocks/CallReceiverMock.sol',
      '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol',
      '@openzeppelin/contracts/utils/cryptography/verifiers/ERC7913P256Verifier.sol',
      '@openzeppelin/contracts/utils/cryptography/verifiers/ERC7913RSAVerifier.sol',
    ],
    settings: {
      optimizer: {
        enabled: true,
        runs: argv.runs,
      },
      evmVersion: argv.evm,
      viaIR: argv.ir,
      outputSelection: { '*': { '*': ['storageLayout'] } },
    },
  },
  networks: {
    default: {
      type: 'edr-simulated',
      hardfork: argv.evm,
      // Exposed contracts often exceed the maximum contract size. For normal contract,
      // we rely on the `code-size` compiler warning, that will cause a compilation error.
      allowUnlimitedContractSize: true,
    },
  },
  test: {
    solidity: {
      fuzz: {
        runs: 5000,
        maxTestRejects: 150000,
      },
      fsPermissions: {
        readDirectory: ['node_modules/hardhat-predeploy/bin'],
      },
    },
  },
  coverage: {
    skipFiles: ['contracts/mocks/**', 'contracts-exposed/**', 'lib/**'],
  },
  warnings: {
    'lib/**/*': 'off',
    'npm/**/*': 'off',
    'test/**/*': 'off',
    'contracts-exposed/**/*': {
      'code-size': 'off',
      'initcode-size': 'off',
    },
    '*': {
      'transient-storage': 'off',
      6335: 'warn', // is-future-solidity-keyword
      default: 'error',
    },
  },
  exposed: {
    imports: true,
    initializers: true,
    include: ['contracts/**/*.sol'],
    exclude: ['**/*WithInit.sol'],
  },
  docgen: await import('./docs/config.mjs').then(m => m.default),
});
