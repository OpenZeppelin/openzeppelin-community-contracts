const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const cloneInitCode = instance => ethers.concat(['0x3d602d80600a3d3981f3', cloneRuntimeCode(instance)]);
const cloneRuntimeCode = instance =>
  ethers.concat([
    '0x363d3d373d3d3d363d73',
    instance.target ?? instance.address ?? instance,
    '0x5af43d82803e903d91602b57fd5bf3',
  ]);

async function fixture() {
  const [other] = await ethers.getSigners();

  // ERC-4337 account implementation. Implementation does not require initial values
  const accountImpl = await ethers.deployContract('$AccountInitializableMock', ['', '']);

  // ERC-4337 factory
  const factory = await ethers.deployContract('$AccountFactory', [accountImpl.target]);

  // Initialize function calldata
  const initializeData = accountImpl.interface.encodeFunctionData('initialize', []);

  return { other, factory, accountImpl, initializeData };
}

describe('AccountFactory', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('predictAddress', function () {
    it('should predict the correct account address', async function () {
      const salt = ethers.randomBytes(32);
      const [predictedAddress, saltedCallData] = await this.factory.predictAddress(salt, this.initializeData);
      const expectedAddress = ethers.getCreate2Address(
        this.factory.target,
        saltedCallData,
        ethers.keccak256(cloneInitCode(this.accountImpl)),
      );
      expect(predictedAddress).to.equal(expectedAddress);
    });

    it('should return the same predicted address for the same salt and calldata', async function () {
      const salt = ethers.randomBytes(32);
      const [predictedAddress1, saltedCallData1] = await this.factory.predictAddress(salt, this.initializeData);
      const [predictedAddress2, saltedCallData2] = await this.factory.predictAddress(salt, this.initializeData);
      expect(predictedAddress1).to.equal(predictedAddress2);
      expect(saltedCallData1).to.equal(saltedCallData2);
    });

    it('should return different addresses for different salts', async function () {
      const salt1 = ethers.randomBytes(32);
      const salt2 = ethers.randomBytes(32);
      const [predictedAddress1] = await this.factory.predictAddress(salt1, this.initializeData);
      const [predictedAddress2] = await this.factory.predictAddress(salt2, this.initializeData);
      expect(predictedAddress1).to.not.equal(predictedAddress2);
    });

    it('should return different addresses for different calldata', async function () {
      const salt = ethers.randomBytes(32);
      const initializeData1 = ethers.concat([this.initializeData, '0x00']);
      const initializeData2 = ethers.concat([this.initializeData, '0x01']);
      const [predictedAddress1] = await this.factory.predictAddress(salt, initializeData1);
      const [predictedAddress2] = await this.factory.predictAddress(salt, initializeData2);
      expect(predictedAddress1).to.not.equal(predictedAddress2);
    });
  });

  describe('cloneAndInitialize', function () {
    it('should create and initialize a new account', async function () {
      const salt = ethers.randomBytes(32);
      const [predictedAddress] = await this.factory.predictAddress(salt, this.initializeData);
      await expect(ethers.provider.getCode(predictedAddress)).to.eventually.equal('0x');
      await this.factory.cloneAndInitialize(salt, this.initializeData);
      await expect(ethers.provider.getCode(predictedAddress)).to.eventually.eq(cloneRuntimeCode(this.accountImpl));

      const deployedClone = this.accountImpl.attach(predictedAddress);
      await expect(deployedClone.initialize()).to.be.reverted;
    });

    it('should return the existing account if already deployed', async function () {
      const salt = ethers.randomBytes(32);

      // First deployment
      await this.factory.cloneAndInitialize(salt, this.initializeData);
      const [cloneAddress1] = await this.factory.predictAddress(salt, this.initializeData);

      // Second deployment attempt (should return the existing clone)
      await this.factory.cloneAndInitialize(salt, this.initializeData);
      const [cloneAddress2] = await this.factory.predictAddress(salt, this.initializeData);

      expect(cloneAddress1).to.equal(cloneAddress2);
    });

    it('should deploy accounts with different salts at different addresses', async function () {
      const salt1 = ethers.randomBytes(32);
      const salt2 = ethers.randomBytes(32);
      await this.factory.cloneAndInitialize(salt1, this.initializeData);
      await this.factory.cloneAndInitialize(salt2, this.initializeData);

      // Addresses differ
      const [predicted1] = await this.factory.predictAddress(salt1, this.initializeData);
      const [predicted2] = await this.factory.predictAddress(salt2, this.initializeData);
      expect(predicted1).to.not.equal(predicted2);

      // Could should be the same regardless
      const code1 = await ethers.provider.getCode(predicted1);
      const code2 = await ethers.provider.getCode(predicted2);
      expect(code1).to.be.eq(code2);
    });
  });
});
