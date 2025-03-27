const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');

const { getDomain } = require('@openzeppelin/contracts/test/helpers/eip712');
const {
  encodeMode,
  encodeSingle,
  CALL_TYPE_CALL,
  MODULE_TYPE_EXECUTOR,
} = require('@openzeppelin/contracts/test/helpers/erc7579');
const time = require('@openzeppelin/contracts/test/helpers/time');

const { ERC4337Helper } = require('../../helpers/erc4337');
const { PackedUserOperation, StartRecovery } = require('../../helpers/eip712-types');

const comp = (a, b) => a > b || -(a < b);

async function fixture() {
  // EOAs and environment
  const [other, ...accounts] = await ethers.getSigners();

  // ERC-7579 validator
  const validator = await ethers.deployContract('$ERC7579ValidatorMock');
  const socialRecovery = await ethers.deployContract('$ERC7579SocialRecovery', ['SocialRecovery', '1']);

  // ERC-4337 signer
  const signer = ethers.Wallet.createRandom();

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const env = await helper.wait();
  const mock = await helper.newAccount('$AccountERC7579Mock', [
    'AccountERC7579',
    '1',
    validator,
    ethers.solidityPacked(['address'], [signer.address]),
  ]);

  // domain cannot be fetched using getDomain(mock) before the mock is deployed
  const domain = {
    name: 'AccountERC7579',
    version: '1',
    chainId: env.chainId,
    verifyingContract: mock.address,
  };

  return { ...env, validator, socialRecovery, domain, mock, signer, other, accounts };
}

describe('ERC7579SocialRecovery', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));

    this.userOp = { nonce: ethers.zeroPadBytes(ethers.hexlify(this.validator.target), 32) };
    this.signUserOp = (userOp, signer = this.signer) =>
      signer
        .signTypedData(this.domain, { PackedUserOperation }, userOp.packed)
        .then(signature => Object.assign(userOp, { signature }));
  });

  describe('with guardians', function () {
    beforeEach(async function () {
      await this.other.sendTransaction({ to: this.mock.target, value: ethers.parseEther('1') });
      await this.mock.deploy();

      this.guardians = [
        { signer: this.accounts[0], weight: 1n },
        { signer: this.accounts[1], weight: 1n },
        { signer: this.accounts[2], weight: 1n },
      ]
        .map(entry =>
          Object.assign(entry, {
            erc7913signer: ethers.solidityPacked(
              ['address', 'bytes'],
              [entry.signer.target ?? entry.signer.address ?? entry.signer, entry.key ?? '0x'],
            ),
            guardian: ethers.solidityPacked(
              ['uint64', 'address', 'bytes'],
              [entry.weight, entry.signer.target ?? entry.signer.address ?? entry.signer, entry.key ?? '0x'],
            ),
          }),
        )
        .sort((g1, g2) =>
          comp(
            ethers.toBigInt(ethers.keccak256(ethers.getBytes(g1.erc7913signer))),
            ethers.toBigInt(ethers.keccak256(ethers.getBytes(g2.erc7913signer))),
          ),
        );

      this.thresholds = [
        { threshold: 2n, lockPeriod: time.duration.days(7n) },
        { threshold: 3n, lockPeriod: time.duration.hours(1n) },
      ];
    });

    it('workflow', async function () {
      // install
      await this.mock
        .createUserOp({
          ...this.userOp,
          target: this.mock.target,
          callData: this.mock.interface.encodeFunctionData('installModule', [
            MODULE_TYPE_EXECUTOR,
            this.socialRecovery.target,
            this.socialRecovery.interface.encodeFunctionData('updateGuardians', [
              this.guardians.map(({ guardian }) => guardian),
              this.thresholds,
            ]),
          ]),
          callGas: 1_000_000n, // TODO: estimate ?
        })
        .then(op => this.signUserOp(op))
        .then(op => entrypoint.handleOps([op.packed], this.other));

      // check config
      await expect(this.socialRecovery.getAccountConfigs(ethers.Typed.address(this.mock))).to.eventually.deep.equal([
        this.guardians.map(({ guardian }) => guardian),
        this.thresholds.map(Object.values),
      ]);

      // prepare recovery
      const socialRecoveryMessage = {
        account: this.mock.target,
        recovery: this.mock.interface.encodeFunctionData('executeFromExecutor', [
          encodeMode({ callType: CALL_TYPE_CALL }),
          encodeSingle(
            this.validator,
            0n,
            this.validator.interface.encodeFunctionData('updateSigner', [this.other.address]),
          ),
        ]),
        nonce: await this.socialRecovery.nonces(this.mock),
      };

      const signatures = await getDomain(this.socialRecovery).then(domain =>
        Promise.all(
          this.guardians.map(({ signer, erc7913signer }) =>
            signer
              .signTypedData(domain, { StartRecovery }, socialRecoveryMessage)
              .then(signature => ({ signer: erc7913signer, signature })),
          ),
        ),
      );

      // start recovery
      await expect(
        this.socialRecovery.startRecovery(
          ethers.Typed.address(socialRecoveryMessage.account),
          socialRecoveryMessage.recovery,
          signatures,
        ),
      )
        .to.emit(this.socialRecovery, 'RecoveryStarted')
        .withArgs(this.mock, socialRecoveryMessage.recovery, anyValue);

      // wait
      await time.increaseBy.timestamp(time.duration.hours(1n));

      // signer before the recovery
      await expect(this.validator.getSigner(this.mock)).to.eventually.equal(this.signer);

      // execute
      await expect(this.socialRecovery.executeRecovery(ethers.Typed.address(socialRecoveryMessage.account)))
        .to.emit(this.socialRecovery, 'RecoveryExecuted')
        .withArgs(this.mock, socialRecoveryMessage.recovery);

      // signer after the recovery
      await expect(this.validator.getSigner(this.mock)).to.eventually.equal(this.other);
    });
  });
});
