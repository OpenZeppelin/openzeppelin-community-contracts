import { network } from 'hardhat';
import { ERC4337Helper } from '@openzeppelin/contracts/test/helpers/erc4337';
import { getDomain, PackedUserOperation } from '@openzeppelin/contracts/test/helpers/eip712';
import { MODULE_TYPE_VALIDATOR } from '@openzeppelin/contracts/test/helpers/erc7579';
import { shouldBehaveLikeERC7579Module, shouldBehaveLikeERC7579Validator } from './ERC7579Module.behavior';

const connection = await network.create();
const {
  ethers,
  helpers: { impersonate },
  networkHelpers: { loadFixture },
} = connection;

async function fixture() {
  const [other] = await ethers.getSigners();

  // Deploy ERC-7579 validator module
  const mock = await ethers.deployContract('$ERC7579Signature');

  // ERC-4337 env
  const helper = new ERC4337Helper(connection);
  await helper.wait();
  const entrypointDomain = await getDomain(ethers.predeploy.entrypoint.v09);

  // Prepare signer
  const signer = ethers.Wallet.createRandom();
  const signUserOp = userOp =>
    signer
      .signTypedData(entrypointDomain, { PackedUserOperation }, userOp.packed)
      .then(signature => Object.assign(userOp, { signature }));

  // Prepare module installation data
  const installData = ethers.solidityPacked(['address'], [signer.address]);

  // ERC-7579 account
  const mockAccount = await helper.newAccount('$AccountERC7579');
  const mockFromAccount = await impersonate(mockAccount.address).then(asAccount => mock.connect(asAccount));

  return {
    moduleType: MODULE_TYPE_VALIDATOR,
    mock,
    mockFromAccount,
    mockAccount,
    other,
    signer,
    signUserOp,
    installData,
  };
}

describe('ERC7579Validator', function () {
  beforeEach(async function () {
    Object.assign(this, connection, await loadFixture(fixture));
  });

  describe('ECDSA key', function () {
    shouldBehaveLikeERC7579Module();
    shouldBehaveLikeERC7579Validator();
  });
});
