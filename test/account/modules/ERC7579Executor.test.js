import { network } from 'hardhat';
import { expect } from 'chai';
import { ERC4337Helper } from '@openzeppelin/contracts/test/helpers/erc4337';
import {
  MODULE_TYPE_EXECUTOR,
  CALL_TYPE_CALL,
  EXEC_TYPE_DEFAULT,
  encodeMode,
  encodeSingle,
} from '@openzeppelin/contracts/test/helpers/erc7579';
import { shouldBehaveLikeERC7579Module } from './ERC7579Module.behavior';

const connection = await network.create();
const {
  ethers,
  helpers: { impersonate },
  networkHelpers: { loadFixture },
} = connection;

async function fixture() {
  // Deploy ERC-7579 validator module
  const mock = await ethers.deployContract('$ERC7579ExecutorMock');
  const target = await ethers.deployContract('CallReceiverMock');

  // ERC-4337 env
  const helper = new ERC4337Helper(connection);
  await helper.wait();

  // Prepare module installation data
  const installData = '0x';

  // ERC-7579 account
  const mockAccount = await helper.newAccount('$AccountERC7579');
  const mockFromAccount = await impersonate(mockAccount.address).then(asAccount => mock.connect(asAccount));

  const moduleType = MODULE_TYPE_EXECUTOR;

  await mockAccount.deploy();
  await impersonate(ethers.predeploy.entrypoint.v09.target).then(asEntrypoint =>
    mockAccount.connect(asEntrypoint).installModule(moduleType, mock.target, installData),
  );

  const args = [42, '0x1234'];
  const data = target.interface.encodeFunctionData('mockFunctionWithArgs', args);
  const calldata = encodeSingle(target, 0, data);
  const mode = encodeMode({ callType: CALL_TYPE_CALL, execType: EXEC_TYPE_DEFAULT });

  return {
    moduleType,
    mock,
    mockAccount,
    mockFromAccount,
    target,
    installData,
    args,
    data,
    calldata,
    mode,
  };
}

describe('ERC7579Executor', function () {
  beforeEach(async function () {
    Object.assign(this, connection, await loadFixture(fixture));
  });

  describe('execute', function () {
    it('succeeds', async function () {
      await expect(this.mockFromAccount.$_execute(this.mockAccount.address, ethers.ZeroHash, this.mode, this.calldata))
        .to.emit(this.mock, 'ERC7579ExecutorOperationExecuted')
        .to.emit(this.target, 'MockFunctionCalledWithArgs')
        .withArgs(...this.args);
    });
  });

  shouldBehaveLikeERC7579Module();
});
