const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ERC4337Helper } = require('../../helpers/erc4337');
const { PackedUserOperation } = require('../../helpers/eip712-types');

const { shouldBehaveLikeAccountCore, shouldBehaveLikeAccountHolder } = require('../Account.behavior');
const { shouldBehaveLikeAccountERC7579 } = require('../extensions/AccountERC7579.behavior');
const { shouldBehaveLikeERC7821 } = require('../extensions/ERC7821.behavior');

const { MODULE_TYPE_VALIDATOR } = require('@openzeppelin/contracts/test/helpers/erc7579');

async function fixture() {
  // EOAs and environment
  const [eoa, beneficiary, other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');
  const anotherTarget = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-4337 signer
  const signer = ethers.Wallet.createRandom();

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const mock = await helper.newAccount('$AccountERC7702WithModulesMock', ['AccountERC7702WithModulesMock', '1'], {
    erc7702signer: eoa,
  });

  // ERC-7579 validator module
  const validator = await ethers.deployContract('$ERC7579ValidatorMock');

  // domain cannot be fetched using getDomain(mock) before the mock is deployed
  const domain = {
    name: 'AccountERC7702WithModulesMock',
    version: '1',
    chainId: env.chainId,
    verifyingContract: mock.address,
  };

  return { ...env, mock, domain, eoa, signer, validator, target, anotherTarget, beneficiary, other };
}

describe('AccountERC7702WithModules: ERC-7702 account with ERC-7579 modules supports', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('using ERC-7702 signer', function () {
    beforeEach(async function () {
      this.signUserOp = userOp =>
        this.eoa
          .signTypedData(this.domain, { PackedUserOperation }, userOp.packed)
          .then(signature => Object.assign(userOp, { signature }));
    });

    shouldBehaveLikeAccountCore();
    shouldBehaveLikeAccountHolder();
    shouldBehaveLikeERC7821({ deployable: false });
  });

  describe('using ERC-7579 validator', function () {
    beforeEach(async function () {
      // Deploy (using ERC-7702) and add the validator module using EOA
      await this.mock.deploy();
      await this.mock.connect(this.eoa).installModule(MODULE_TYPE_VALIDATOR, this.validator, this.signer.address);

      this.signUserOp = userOp =>
        this.signer
          .signTypedData(this.domain, { PackedUserOperation }, userOp.packed)
          .then(signature => Object.assign(userOp, { signature }));

      // Use the first 20 bytes from the nonce key (24 bytes) to identify the validator module
      this.userOp = { nonce: ethers.zeroPadBytes(ethers.hexlify(this.validator.target), 32) };
    });

    shouldBehaveLikeAccountCore();
    shouldBehaveLikeAccountHolder();
    shouldBehaveLikeAccountERC7579();
  });
});
