const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { getDomain } = require('@openzeppelin/contracts/test/helpers/eip712');
const { ERC7739Signer } = require('@openzeppelin/contracts/test/helpers/erc7739');
const { encodeMode, encodeBatch, CALL_TYPE_BATCH } = require('@openzeppelin/contracts/test/helpers/erc7579');
const { shouldBehaveLikeERC1271 } = require('@openzeppelin/contracts/test/utils/cryptography/ERC1271.behavior');

const ERC1271_MAGIC_VALUE = '0x1626ba7e';
const ROLE = 42n;

// Wraps a signer so that its produced signatures are prefixed with the signer's address, matching the
// `[20-byte signer address][inner signature]` layout expected by RoleSigner. The ERC7739Signer helper
// then appends the ERC-7739 envelope (for typed data) on top of this inner signature.
class RoleMemberSigner extends ethers.AbstractSigner {
  #signer;

  constructor(signer) {
    super(signer.provider);
    this.#signer = signer;
  }

  getAddress() {
    return this.#signer.getAddress();
  }

  connect(provider) {
    return new RoleMemberSigner(this.#signer.connect(provider));
  }

  signTransaction(tx) {
    return this.#signer.signTransaction(tx);
  }

  signMessage(message) {
    return this.#signer.signMessage(message);
  }

  async signTypedData(domain, types, value) {
    return ethers.concat([await this.#signer.getAddress(), await this.#signer.signTypedData(domain, types, value)]);
  }
}

async function fixture() {
  const [admin, member, other] = await ethers.getSigners();

  const manager = await ethers.deployContract('$AccessManagerWithRoleAccounts', [admin.address]);

  // Deploy the role account for ROLE and grant the role to `member`.
  const predicted = await manager.getRoleAccount(ROLE);
  await manager.deployRoleAccount(ROLE);
  const account = await ethers.getContractAt('RoleAccount', predicted);
  await manager.connect(admin).grantRole(ROLE, member.address, 0);

  return { admin, member, other, manager, account, predicted };
}

describe('AccessManagerWithRoleAccounts', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('role account deployment', function () {
    it('deploys the role account at the predicted deterministic address', async function () {
      await expect(ethers.provider.getCode(this.predicted)).to.eventually.not.equal('0x');
    });

    it('getRoleAccount matches the address returned by deployRoleAccount', async function () {
      const otherRole = 7n;
      await expect(this.manager.deployRoleAccount.staticCall(otherRole)).to.eventually.equal(
        await this.manager.getRoleAccount(otherRole),
      );
    });

    it('reverts when deploying the same role twice', async function () {
      await expect(this.manager.deployRoleAccount(ROLE)).to.be.reverted;
    });

    it('exposes the role id decoded from the clone immutable args', async function () {
      expect(await this.account.roleId()).to.equal(ROLE);
    });
  });

  describe('ERC-1271 / ERC-7739 signature validation', function () {
    beforeEach(function () {
      this.mock = this.account;
      this.signer = new RoleMemberSigner(this.member);
    });

    shouldBehaveLikeERC1271({ erc7739: true });

    it('rejects a signature from a non-member', async function () {
      const domain = await getDomain(this.account);
      const signer = new ERC7739Signer(new RoleMemberSigner(this.other), domain);

      const text = 'authorize me';
      const hash = ethers.hashMessage(text);
      const signature = await signer.signMessage(text);

      expect(await this.account.isValidSignature(hash, signature)).to.not.equal(ERC1271_MAGIC_VALUE);
    });
  });

  describe('ERC-7821 execution', function () {
    beforeEach(async function () {
      this.target = await ethers.deployContract('CallReceiverMock');
      this.mode = encodeMode({ callType: CALL_TYPE_BATCH });
      this.data = encodeBatch([this.target, 0n, this.target.interface.encodeFunctionData('mockFunction')]);
    });

    it('authorizes execution triggered by a role member', async function () {
      await expect(this.account.connect(this.member).execute(this.mode, this.data)).to.emit(
        this.target,
        'MockFunctionCalled',
      );
    });

    it('rejects execution triggered by a non-member', async function () {
      await expect(this.account.connect(this.other).execute(this.mode, this.data))
        .to.be.revertedWithCustomError(this.account, 'AccountUnauthorized')
        .withArgs(this.other.address);
    });
  });
});
