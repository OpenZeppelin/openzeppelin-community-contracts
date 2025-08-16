const { ethers, predeploy } = require('hardhat');
const { expect } = require('chai');
const { loadFixture, time } = require('@nomicfoundation/hardhat-network-helpers');

const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');
const { getDomain } = require('@openzeppelin/contracts/test/helpers/eip712');
const { ERC4337Helper } = require('@openzeppelin/contracts/test/helpers/erc4337');
const { MODULE_TYPE_EXECUTOR } = require('@openzeppelin/contracts/test/helpers/erc7579');
const { MultisigConfirmation } = require('../../helpers/eip712-types');

const { shouldBehaveLikeERC7579Module } = require('./ERC7579Module.behavior');

// Prepare signers in advance
const initialSigner = ethers.Wallet.createRandom();
const signerToConfirm = ethers.Wallet.createRandom();

async function fixture() {
  // Deploy ERC-7579 multisig confirmation module
  const mock = await ethers.deployContract('$ERC7579MultisigConfirmationExecutorMock', [
    'ERC7579MultisigConfirmation',
    '1',
  ]);

  // ERC-4337 env
  const helper = new ERC4337Helper();
  await helper.wait();

  // ERC-7579 account
  const mockAccount = await helper.newAccount('$AccountERC7579');
  const mockFromAccount = await impersonate(mockAccount.address).then(asAccount => mock.connect(asAccount));
  const mockAccountFromEntrypoint = await impersonate(predeploy.entrypoint.v08.target).then(asEntrypoint =>
    mockAccount.connect(asEntrypoint),
  );

  // Get the EIP-712 domain for the mock module
  const domain = await getDomain(mock);

  // Prepare module installation data
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  const signers = abiCoder.encode(
    ['uint256', 'bytes', 'bytes'],
    [
      (await time.latest()) + time.duration.days(1),
      initialSigner.address,
      await initialSigner.signTypedData(
        domain,
        { MultisigConfirmation },
        {
          account: mockAccount.address,
          module: mock.target,
          deadline: (await time.latest()) + time.duration.days(1),
        },
      ),
    ],
  );
  const installData = abiCoder.encode(['bytes[]', 'uint64'], [[signers], 1]);

  const moduleType = MODULE_TYPE_EXECUTOR;

  await mockAccount.deploy();
  await mockAccountFromEntrypoint.installModule(moduleType, mock.target, installData);

  return {
    moduleType,
    mock,
    mockAccount,
    mockFromAccount,
    domain,
  };
}

describe('ERC7579MultisigConfirmation', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  shouldBehaveLikeERC7579Module();

  describe('signer confirmation', function () {
    it('can add a signer with valid confirmation signature', async function () {
      // Create future deadline for signature validity
      const deadline = (await time.latest()) + time.duration.days(1);

      // Generate the typed data hash for confirmation
      const typedData = {
        account: this.mockAccount.address,
        module: this.mock.target,
        deadline: deadline,
      };

      // Sign the confirmation message with the signer to be added
      const signature = await signerToConfirm.signTypedData(this.domain, { MultisigConfirmation }, typedData);

      // Encode the new signer with deadline and signature
      const encodedSigner = ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256', 'bytes', 'bytes'],
        [deadline, signerToConfirm.address, signature],
      );

      // Add the new signer with confirmation
      await expect(this.mockFromAccount.addSigners([encodedSigner]))
        .to.emit(this.mock, 'ERC7913SignerAdded')
        .withArgs(this.mockAccount.address, signerToConfirm.address.toLowerCase());

      // Verify the signer was added
      await expect(this.mock.isSigner(this.mockAccount.address, signerToConfirm.address)).to.eventually.be.true;
    });

    it('rejects adding a signer with expired deadline', async function () {
      // Create expired deadline
      const deadline = (await time.latest()) - 1;

      // Generate the typed data hash for confirmation
      const typedData = {
        account: this.mockAccount.address,
        module: this.mock.target,
        deadline: deadline,
      };

      // Sign the confirmation message with signerToConfirm
      const signature = await signerToConfirm.signTypedData(this.domain, { MultisigConfirmation }, typedData);

      // Encode the new signer with expired deadline and signature
      const encodedSigner = ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256', 'bytes', 'bytes'],
        [deadline, signerToConfirm.address, signature],
      );

      // Should fail due to expired deadline
      await expect(this.mockFromAccount.addSigners([encodedSigner]))
        .to.be.revertedWithCustomError(this.mock, 'ERC7579MultisigExpiredConfirmation')
        .withArgs(deadline);
    });

    it('rejects adding a signer with invalid signature', async function () {
      // Create future deadline for signature validity
      const deadline = (await time.latest()) + time.duration.days(1);

      // Generate typed data for a different account (invalid for our target)
      const typedData = {
        account: ethers.Wallet.createRandom().address, // Different account
        module: this.mock.target,
        deadline: deadline,
      };

      // Sign the invalid confirmation message with signerToConfirm
      const signature = await signerToConfirm.signTypedData(this.domain, { MultisigConfirmation }, typedData);

      // Encode the new signer with deadline and invalid signature
      const encodedSigner = ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256', 'bytes', 'bytes'],
        [deadline, signerToConfirm.address, signature],
      );

      // Should fail due to invalid signature
      await expect(this.mockFromAccount.addSigners([encodedSigner]))
        .to.be.revertedWithCustomError(this.mock, 'ERC7579MultisigInvalidConfirmationSignature')
        .withArgs(signerToConfirm.address.toLowerCase());
    });

    it('can add multiple signers with valid confirmation signatures', async function () {
      // Create future deadline for signature validity
      const deadline = (await time.latest()) + time.duration.days(1);

      // Create another signer to add
      const anotherSigner = ethers.Wallet.createRandom();

      // Generate the typed data for both signers
      const typedData = {
        account: this.mockAccount.address,
        module: this.mock.target,
        deadline: deadline,
      };

      // Each signer signs their own confirmation
      const signature1 = await signerToConfirm.signTypedData(this.domain, { MultisigConfirmation }, typedData);
      const signature2 = await anotherSigner.signTypedData(this.domain, { MultisigConfirmation }, typedData);

      // Encode both signers with their respective signatures
      const encodedSigner1 = ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256', 'bytes', 'bytes'],
        [deadline, signerToConfirm.address, signature1],
      );

      const encodedSigner2 = ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256', 'bytes', 'bytes'],
        [deadline, anotherSigner.address, signature2],
      );

      // Add both signers with confirmation
      await expect(this.mockFromAccount.addSigners([encodedSigner1, encodedSigner2]))
        .to.emit(this.mock, 'ERC7913SignerAdded')
        .withArgs(this.mockAccount.address, signerToConfirm.address.toLowerCase())
        .to.emit(this.mock, 'ERC7913SignerAdded')
        .withArgs(this.mockAccount.address, anotherSigner.address.toLowerCase());

      // Verify both signers were added
      await expect(this.mock.isSigner(this.mockAccount.address, signerToConfirm.address)).to.eventually.be.true;
      await expect(this.mock.isSigner(this.mockAccount.address, anotherSigner.address)).to.eventually.be.true;
    });

    it('fails to add multiple signers if any signature is invalid', async function () {
      // Create future deadline for signature validity
      const deadline = (await time.latest()) + time.duration.days(1);

      // Create another signer to add
      const anotherSigner = ethers.Wallet.createRandom();

      // Generate valid typed data
      const validTypedData = {
        account: this.mockAccount.address,
        module: this.mock.target,
        deadline: deadline,
      };

      // Generate invalid typed data with different account
      const invalidTypedData = {
        account: ethers.Wallet.createRandom().address,
        module: this.mock.target,
        deadline: deadline,
      };

      // Sign messages - one valid, one invalid
      const validSignature = await signerToConfirm.signTypedData(this.domain, { MultisigConfirmation }, validTypedData);
      const invalidSignature = await anotherSigner.signTypedData(
        this.domain,
        { MultisigConfirmation },
        invalidTypedData,
      );

      // Encode both signers
      const encodedSigner1 = ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256', 'bytes', 'bytes'],
        [deadline, signerToConfirm.address, validSignature],
      );

      const encodedSigner2 = ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256', 'bytes', 'bytes'],
        [deadline, anotherSigner.address, invalidSignature],
      );

      // Should fail due to invalid signature for signer4
      await expect(this.mockFromAccount.addSigners([encodedSigner1, encodedSigner2]))
        .to.be.revertedWithCustomError(this.mock, 'ERC7579MultisigInvalidConfirmationSignature')
        .withArgs(anotherSigner.address.toLowerCase());

      // Verify neither signer was added
      await expect(this.mock.isSigner(this.mockAccount.address, signerToConfirm.address)).to.eventually.be.false;
      await expect(this.mock.isSigner(this.mockAccount.address, anotherSigner.address)).to.eventually.be.false;
    });

    it('still allows removing signers without confirmation', async function () {
      // First, add a signer with valid confirmation
      const deadline = (await time.latest()) + time.duration.days(1);
      const typedData = {
        account: this.mockAccount.address,
        module: this.mock.target,
        deadline: deadline,
      };
      const signature = await signerToConfirm.signTypedData(this.domain, { MultisigConfirmation }, typedData);
      const encodedSigner = ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256', 'bytes', 'bytes'],
        [deadline, signerToConfirm.address, signature],
      );

      await this.mockFromAccount.addSigners([encodedSigner]);

      // Now remove the signer (no confirmation required for removal)
      await expect(this.mockFromAccount.removeSigners([signerToConfirm.address]))
        .to.emit(this.mock, 'ERC7913SignerRemoved')
        .withArgs(this.mockAccount.address, signerToConfirm.address.toLowerCase());

      // Verify signer was removed
      await expect(this.mock.isSigner(this.mockAccount.address, signerToConfirm.address)).to.eventually.be.false;
    });
  });
});
