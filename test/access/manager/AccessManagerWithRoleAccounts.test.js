const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { getDomain } = require('@openzeppelin/contracts/test/helpers/eip712');
const { ERC7739Signer } = require('@openzeppelin/contracts/test/helpers/erc7739');
const { encodeMode, encodeBatch, CALL_TYPE_BATCH } = require('@openzeppelin/contracts/test/helpers/erc7579');
const { shouldBehaveLikeERC1271 } = require('@openzeppelin/contracts/test/utils/cryptography/ERC1271.behavior');

const ERC1271_MAGIC_VALUE = '0x1626ba7e';
const ROLE = 42n;
const OTHER_ROLE = 17n;

// Wraps a signer so that its produced signatures are prefixed with the signer's address, matching the
// `[20-byte signer address][inner signature]` layout expected by RoleSigner. The ERC7739Signer helper
// then appends the ERC-7739 envelope (for typed data) on top of this inner signature.
class RoleMemberSigner extends ethers.AbstractSigner {
  #signer;

  constructor(signer) {
    super(signer.provider);
    this.#signer = signer;
  }

  static from(...args) {
    return new this(...args);
  }

  getAddress() {
    return this.#signer.getAddress();
  }

  connect(provider) {
    return new RoleMemberSigner(this.#signer.connect(provider));
  }

  // Note: because this is used within an ERC-7739 context, only signTypedData is needed.
  // ERC-191 are wrapped in EIP-712 structs, and signed as such following ERC-7739.
  signTypedData(domain, types, value) {
    return Promise.all([this.#signer.getAddress(), this.#signer.signTypedData(domain, types, value)]).then(
      ethers.concat,
    );
  }
}

async function fixture() {
  const [admin, member, delayed, other] = await ethers.getSigners();

  const manager = await ethers.deployContract('$AccessManagerWithRoleAccounts', [admin]);
  await manager.connect(admin).grantRole(ROLE, member, 0n);
  await manager.connect(admin).grantRole(ROLE, delayed, 1n);

  // Deploy the role account for ROLE and grant the role to `member`.
  const account = await manager.getRoleAccount(ROLE).then(predicted => ethers.getContractAt('RoleAccount', predicted));
  await manager.deployRoleAccount(ROLE);

  return { admin, member, delayed, other, manager, account };
}

describe('AccessManagerWithRoleAccounts', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('role account deployment', function () {
    it('deploys the role account at the predicted deterministic address', async function () {
      await expect(ethers.provider.getCode(this.account)).to.eventually.not.equal('0x');
    });

    it('getRoleAccount matches the address returned by deployRoleAccount', async function () {
      const predicted = await this.manager.getRoleAccount(OTHER_ROLE);
      await expect(this.manager.deployRoleAccount.staticCall(OTHER_ROLE)).to.eventually.equal(predicted);
    });

    it('reverts when deploying the same role twice', async function () {
      await expect(this.manager.deployRoleAccount(ROLE)).to.be.reverted;
    });

    it('exposes the role id decoded from the clone immutable args', async function () {
      await expect(this.account.roleId()).to.eventually.equal(ROLE);
    });
  });

  describe('ERC-1271 / ERC-7739 signature validation', function () {
    beforeEach(function () {
      this.mock = this.account;
      this.signer = RoleMemberSigner.from(this.member);
    });

    shouldBehaveLikeERC1271({ erc7739: true });

    it('rejects a signature from a non-member', async function () {
      const domain = await getDomain(this.account);
      const text = 'authorize me';

      // by valid signer
      await expect(
        this.account.isValidSignature(
          ethers.hashMessage(text),
          ERC7739Signer.from(RoleMemberSigner.from(this.member), domain).signMessage(text),
        ),
      ).to.eventually.equal(ERC1271_MAGIC_VALUE);

      // by a signer with delay
      await expect(
        this.account.isValidSignature(
          ethers.hashMessage(text),
          ERC7739Signer.from(RoleMemberSigner.from(this.delayed), domain).signMessage(text),
        ),
      ).to.eventually.not.equal(ERC1271_MAGIC_VALUE);

      // by other signer
      await expect(
        this.account.isValidSignature(
          ethers.hashMessage(text),
          ERC7739Signer.from(RoleMemberSigner.from(this.other), domain).signMessage(text),
        ),
      ).to.eventually.not.equal(ERC1271_MAGIC_VALUE);
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

    it('rejects execution triggered by a role member with a delay', async function () {
      await expect(this.account.connect(this.delayed).execute(this.mode, this.data))
        .to.be.revertedWithCustomError(this.account, 'AccountUnauthorized')
        .withArgs(this.delayed.address);
    });

    it('rejects execution triggered by a non-member', async function () {
      await expect(this.account.connect(this.other).execute(this.mode, this.data))
        .to.be.revertedWithCustomError(this.account, 'AccountUnauthorized')
        .withArgs(this.other.address);
    });
  });
});
