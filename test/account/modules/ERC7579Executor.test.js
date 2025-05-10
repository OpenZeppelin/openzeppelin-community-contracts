const { ethers } = require('hardhat');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');
const { ERC4337Helper } = require('../../helpers/erc4337');

const { MODULE_TYPE_EXECUTOR } = require('@openzeppelin/contracts/test/helpers/erc7579');
const { shouldBehaveLikeERC7579Module, shouldBehaveLikeERC7579Executor } = require('./ERC7579Module.behavior');

async function fixture() {
  const [other] = await ethers.getSigners();

  // Deploy ERC-7579 validator module
  const mock = await ethers.deployContract('$ERC7579ExecutorMock');
  const target = await ethers.deployContract('CallReceiverMockExtended');

  // ERC-4337 env
  const helper = new ERC4337Helper();
  await helper.wait();

  // Prepare module installation data
  const installData = '0x';

  // ERC-7579 account
  const mockAccount = await helper.newAccount('$AccountERC7579');
  const mockFromAccount = await impersonate(mockAccount.address).then(asAccount => mock.connect(asAccount));

  return {
    moduleType: MODULE_TYPE_EXECUTOR,
    mock,
    mockAccount,
    mockFromAccount,
    other,
    target,
    installData,
  };
}

describe('ERC7579Validator', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeERC7579Module();
  shouldBehaveLikeERC7579Executor();
});
