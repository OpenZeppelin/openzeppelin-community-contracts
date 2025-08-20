const { ethers, predeploy } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');
const { ERC4337Helper } = require('@openzeppelin/contracts/test/helpers/erc4337');
const { NonNativeSigner, MultiERC7913SigningKey } = require('@openzeppelin/contracts/test/helpers/signers');

const {
  MODULE_TYPE_EXECUTOR,
  CALL_TYPE_CALL,
  EXEC_TYPE_DEFAULT,
  encodeMode,
  encodeSingle,
} = require('@openzeppelin/contracts/test/helpers/erc7579');
const { shouldBehaveLikeERC7579Module } = require('./ERC7579Module.behavior');

// Prepare signers in advance
const signerECDSA1 = ethers.Wallet.createRandom();
const signerECDSA2 = ethers.Wallet.createRandom();
const signerECDSA3 = ethers.Wallet.createRandom();
const signerECDSA4 = ethers.Wallet.createRandom(); // Unauthorized signer

async function fixture() {
  // Deploy ERC-7579 multisig storage module
  const mock = await ethers.deployContract('$ERC7579MultisigStorageExecutorMock', ['MultisigStorageExecutor', '1']);
  const target = await ethers.deployContract('CallReceiverMock');

  // ERC-4337 env
  const helper = new ERC4337Helper();
  await helper.wait();

  // Prepare signers
  const signers = [signerECDSA1.address, signerECDSA2.address];
  const threshold = 1;
  const multiSigner = new NonNativeSigner(new MultiERC7913SigningKey([signerECDSA1, signerECDSA2]));

  // Prepare module installation data
  const installData = ethers.AbiCoder.defaultAbiCoder().encode(['bytes[]', 'uint256'], [signers, threshold]);

  // ERC-7579 account
  const mockAccount = await helper.newAccount('$AccountERC7579');
  const mockFromAccount = await impersonate(mockAccount.address).then(asAccount => mock.connect(asAccount));
  const mockAccountFromEntrypoint = await impersonate(predeploy.entrypoint.v08.target).then(asEntrypoint =>
    mockAccount.connect(asEntrypoint),
  );

  const moduleType = MODULE_TYPE_EXECUTOR;

  await mockAccount.deploy();

  const args = [42, '0x1234'];
  const data = target.interface.encodeFunctionData('mockFunctionWithArgs', args);
  const calldata = encodeSingle(target, 0, data);
  const mode = encodeMode({ callType: CALL_TYPE_CALL, execType: EXEC_TYPE_DEFAULT });

  return {
    moduleType,
    mock,
    mockAccount,
    mockFromAccount,
    mockAccountFromEntrypoint,
    target,
    installData,
    args,
    data,
    calldata,
    mode,
    signers,
    threshold,
    multiSigner,
  };
}

describe('ERC7579MultisigStorage', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
    await this.mockAccountFromEntrypoint.installModule(this.moduleType, this.mock.target, this.installData);
  });

  shouldBehaveLikeERC7579Module();

  describe('presigning functionality', function () {
    it('allows presigning valid signatures', async function () {
      const testMessage = 'test';
      const messageHash = ethers.hashMessage(testMessage);
      const signature = await signerECDSA1.signMessage(testMessage);

      // Presign should succeed and emit event
      await expect(this.mock.presign(this.mockAccount.address, signerECDSA1.address, messageHash, signature))
        .to.emit(this.mock, 'ERC7579MultisigStoragePresigned')
        .withArgs(this.mockAccount.address, messageHash, signerECDSA1.address.toLowerCase());

      // Check that signature is marked as presigned
      await expect(this.mock.presigned(this.mockAccount.address, signerECDSA1.address, messageHash)).to.eventually.be
        .true;
    });

    it('allows presigning from unauthorized signers', async function () {
      const testMessage = 'test';
      const messageHash = ethers.hashMessage(testMessage);
      const signature = await signerECDSA4.signMessage(testMessage); // Unauthorized signer

      // Presign should succeed even for unauthorized signer (cryptographically valid)
      await expect(this.mock.presign(this.mockAccount.address, signerECDSA4.address, messageHash, signature))
        .to.emit(this.mock, 'ERC7579MultisigStoragePresigned')
        .withArgs(this.mockAccount.address, messageHash, signerECDSA4.address.toLowerCase());

      // Check that signature is marked as presigned
      await expect(this.mock.presigned(this.mockAccount.address, signerECDSA4.address, messageHash)).to.eventually.be
        .true;
    });

    it('rejects invalid signatures during presigning', async function () {
      const testMessage = 'test';
      const differentMessage = 'different';
      const messageHash = ethers.hashMessage(testMessage);
      const invalidSignature = await signerECDSA1.signMessage(differentMessage);

      // Presign should fail silently for invalid signature (no event, no revert)
      await expect(
        this.mock.presign(this.mockAccount.address, signerECDSA1.address, messageHash, invalidSignature),
      ).to.not.emit(this.mock, 'ERC7579MultisigStoragePresigned');

      // Check that signature is NOT marked as presigned
      await expect(this.mock.presigned(this.mockAccount.address, signerECDSA1.address, messageHash)).to.eventually.be
        .false;
    });

    it('ignores duplicate presigning attempts', async function () {
      const testMessage = 'test';
      const messageHash = ethers.hashMessage(testMessage);
      const signature = await signerECDSA1.signMessage(testMessage);

      // First presign should succeed
      await expect(this.mock.presign(this.mockAccount.address, signerECDSA1.address, messageHash, signature)).to.emit(
        this.mock,
        'ERC7579MultisigStoragePresigned',
      );

      // Second presign should be a no-op (no event)
      await expect(
        this.mock.presign(this.mockAccount.address, signerECDSA1.address, messageHash, signature),
      ).to.not.emit(this.mock, 'ERC7579MultisigStoragePresigned');
    });
  });

  describe('validation with presigned signatures', function () {
    it('validates with only presigned signatures', async function () {
      const testMessage = 'test';
      const messageHash = ethers.hashMessage(testMessage);
      const signature = await signerECDSA1.signMessage(testMessage);

      // Presign the signature
      await this.mock.presign(this.mockAccount.address, signerECDSA1.address, messageHash, signature);

      // Create validation data with empty signature (indicates presigned)
      const signingSigners = [signerECDSA1.address];
      const signatures = ['0x']; // Empty signature indicates presigned
      const validationData = ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes[]', 'bytes[]'],
        [signingSigners, signatures],
      );

      // Should succeed with presigned signature
      await expect(this.mock.$_rawERC7579Validation(this.mockAccount.address, messageHash, validationData)).to
        .eventually.be.true;
    });

    it('validates with mixed presigned and regular signatures', async function () {
      // Set threshold to 2 to require both signatures
      await this.mockFromAccount.setThreshold(2);

      const testMessage = 'test';
      const messageHash = ethers.hashMessage(testMessage);

      // Presign one signature
      const presignedSignature = await signerECDSA1.signMessage(testMessage);
      await this.mock.presign(this.mockAccount.address, signerECDSA1.address, messageHash, presignedSignature);

      // Create regular signature
      const regularSignature = await signerECDSA2.signMessage(testMessage);

      // Create validation data with mixed signatures
      const signingSigners = [signerECDSA1.address, signerECDSA2.address];
      const signatures = ['0x', regularSignature]; // First empty (presigned), second regular
      const validationData = ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes[]', 'bytes[]'],
        [signingSigners, signatures],
      );

      // Should succeed with mixed signatures
      await expect(this.mock.$_rawERC7579Validation(this.mockAccount.address, messageHash, validationData)).to
        .eventually.be.true;
    });

    it('rejects presigned signatures from unauthorized signers', async function () {
      const testMessage = 'test';
      const messageHash = ethers.hashMessage(testMessage);
      const signature = await signerECDSA4.signMessage(testMessage); // Unauthorized signer

      // Presign the signature (should succeed)
      await this.mock.presign(this.mockAccount.address, signerECDSA4.address, messageHash, signature);

      // Create validation data with empty signature (indicates presigned)
      const signingSigners = [signerECDSA4.address];
      const signatures = ['0x'];
      const validationData = ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes[]', 'bytes[]'],
        [signingSigners, signatures],
      );

      // Should fail because signer is not authorized
      await expect(this.mock.$_rawERC7579Validation(this.mockAccount.address, messageHash, validationData)).to
        .eventually.be.false;
    });

    it('rejects when presigned signature was not actually presigned', async function () {
      const testMessage = 'test';
      const messageHash = ethers.hashMessage(testMessage);

      // Don't presign, just try to use empty signature
      const signingSigners = [signerECDSA1.address];
      const signatures = ['0x']; // Empty signature indicates presigned
      const validationData = ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes[]', 'bytes[]'],
        [signingSigners, signatures],
      );

      // Should fail because signature was not presigned
      await expect(this.mock.$_rawERC7579Validation(this.mockAccount.address, messageHash, validationData)).to
        .eventually.be.false;
    });

    it('rejects when threshold not met with presigned signatures', async function () {
      // Set threshold to 2
      await this.mockFromAccount.setThreshold(2);

      const testMessage = 'test';
      const messageHash = ethers.hashMessage(testMessage);
      const signature = await signerECDSA1.signMessage(testMessage);

      // Presign only one signature
      await this.mock.presign(this.mockAccount.address, signerECDSA1.address, messageHash, signature);

      // Create validation data with only one presigned signature
      const signingSigners = [signerECDSA1.address];
      const signatures = ['0x'];
      const validationData = ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes[]', 'bytes[]'],
        [signingSigners, signatures],
      );

      // Should fail because threshold (2) is not met
      await expect(this.mock.$_rawERC7579Validation(this.mockAccount.address, messageHash, validationData)).to
        .eventually.be.false;
    });
  });

  describe('edge cases', function () {
    it('handles empty signer arrays', async function () {
      const testMessage = 'test';
      const messageHash = ethers.hashMessage(testMessage);

      const validationData = ethers.AbiCoder.defaultAbiCoder().encode(['bytes[]', 'bytes[]'], [[], []]);

      // Should fail because no signers provided
      await expect(this.mock.$_rawERC7579Validation(this.mockAccount.address, messageHash, validationData)).to
        .eventually.be.false;
    });

    it('maintains original multisig functionality for regular signatures', async function () {
      // This test ensures the storage extension doesn't break regular signature validation
      const testMessage = 'test';
      const messageHash = ethers.hashMessage(testMessage);
      const multiSignature = await this.multiSigner.signMessage(testMessage);

      // Should work exactly like the base multisig
      await expect(this.mock.$_rawERC7579Validation(this.mockAccount.address, messageHash, multiSignature)).to
        .eventually.be.true;
    });

    it('correctly filters presigned vs regular signatures', async function () {
      // Set threshold to 2
      await this.mockFromAccount.setThreshold(2);

      const testMessage = 'test';
      const messageHash = ethers.hashMessage(testMessage);

      // Presign one signature
      const presignedSignature = await signerECDSA1.signMessage(testMessage);
      await this.mock.presign(this.mockAccount.address, signerECDSA1.address, messageHash, presignedSignature);

      // Create regular signature
      const regularSignature = await signerECDSA2.signMessage(testMessage);

      // Test with presigned first, then regular
      let signingSigners = [signerECDSA1.address, signerECDSA2.address];
      let signatures = ['0x', regularSignature];
      let validationData = ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes[]', 'bytes[]'],
        [signingSigners, signatures],
      );
      await expect(this.mock.$_rawERC7579Validation(this.mockAccount.address, messageHash, validationData)).to
        .eventually.be.true;

      // Test with regular first, then presigned
      signingSigners = [signerECDSA2.address, signerECDSA1.address];
      signatures = [regularSignature, '0x'];
      validationData = ethers.AbiCoder.defaultAbiCoder().encode(['bytes[]', 'bytes[]'], [signingSigners, signatures]);
      await expect(this.mock.$_rawERC7579Validation(this.mockAccount.address, messageHash, validationData)).to
        .eventually.be.true;
    });
  });

  describe('integration with base functionality', function () {
    it('still validates signer authorization for regular signatures', async function () {
      const testMessage = 'test';
      const messageHash = ethers.hashMessage(testMessage);

      // Create signature from unauthorized signer
      const unauthorizedSignature = await signerECDSA4.signMessage(testMessage);

      const signingSigners = [signerECDSA4.address];
      const signatures = [unauthorizedSignature];
      const validationData = ethers.AbiCoder.defaultAbiCoder().encode(
        ['bytes[]', 'bytes[]'],
        [signingSigners, signatures],
      );

      // Should fail because signer is not authorized (same as base multisig)
      await expect(this.mock.$_rawERC7579Validation(this.mockAccount.address, messageHash, validationData)).to
        .eventually.be.false;
    });

    it('inherits signer management functionality', async function () {
      // Test that we can still add/remove signers like the base contract
      const newSigners = [signerECDSA3.address];

      for (const signer of newSigners) {
        await expect(this.mockFromAccount.addSigners([signer]))
          .to.emit(this.mock, 'ERC7913SignerAdded')
          .withArgs(this.mockAccount.address, signer.toLowerCase());
      }

      await expect(this.mock.isSigner(this.mockAccount.address, signerECDSA3.address)).to.eventually.be.true;
    });
  });
});
