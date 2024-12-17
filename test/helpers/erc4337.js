const { ethers } = require('hardhat');
const { UserOperation } = require('@openzeppelin/contracts/test/helpers/erc4337');
const { deployEntrypoint } = require('@openzeppelin/contracts/test/helpers/erc4337-entrypoint');

/// Global ERC-4337 environment helper.
class ERC4337Helper {
  constructor(account, params = {}) {
    this.entrypointAsPromise = deployEntrypoint();
    this.factoryAsPromise = ethers.deployContract('Create2Mock');
    this.accountContractAsPromise = ethers.getContractFactory(account);
    this.chainIdAsPromise = ethers.provider.getNetwork().then(({ chainId }) => chainId);
    this.params = params;
  }

  async wait() {
    const { entrypoint, sendercreator } = await this.entrypointAsPromise;

    this.entrypoint = entrypoint;
    this.senderCreator = sendercreator;
    this.factory = await this.factoryAsPromise;
    this.accountContract = await this.accountContractAsPromise;
    this.chainId = await this.chainIdAsPromise;

    return this;
  }

  async newAccount(extraArgs = [], salt = ethers.randomBytes(32)) {
    await this.wait();
    const initCode = await this.accountContract
      .getDeployTransaction(...extraArgs)
      .then(tx => this.factory.interface.encodeFunctionData('$deploy', [0, salt, tx.data]))
      .then(deployCode => ethers.concat([this.factory.target, deployCode]));
    const instance = await this.senderCreator.createSender
      .staticCall(initCode)
      .then(address => this.accountContract.attach(address));
    return new SmartAccount(instance, initCode, this);
  }
}

/// Represent one ERC-4337 account contract.
class SmartAccount extends ethers.BaseContract {
  constructor(instance, initCode, context) {
    super(instance.target, instance.interface, instance.runner, instance.deployTx);
    this.address = instance.target;
    this.initCode = initCode;
    this.factory = '0x' + initCode.replace(/0x/, '').slice(0, 40);
    this.factoryData = '0x' + initCode.replace(/0x/, '').slice(40);
    this.context = context;
  }

  async deploy(account = this.runner) {
    this.deployTx = await account.sendTransaction({
      to: this.factory,
      data: this.factoryData,
    });
    return this;
  }

  async createOp(args = {}) {
    await this.context.wait();

    const params = Object.assign({ sender: this }, args);
    // fetch nonce
    if (!params.nonce) {
      params.nonce = await this.context.entrypoint.getNonce(this, 0);
    }
    // prepare paymaster and data
    if (ethers.isAddressable(params.paymaster)) {
      params.paymaster = await ethers.resolveAddress(params.paymaster);
      params.paymasterVerificationGasLimit ??= 100_000n;
      params.paymasterPostOpGasLimit ??= 100_000n;
      params.paymasterAndData = ethers.solidityPacked(
        ['address', 'uint128', 'uint128'],
        [params.paymaster, params.paymasterVerificationGasLimit, params.paymasterPostOpGasLimit],
      );
    }

    return new UserOperationWithContext(params);
  }
}

class UserOperationWithContext extends UserOperation {
  constructor(params) {
    super(params);
    this.context = params.sender.context;
    this.initCode = {
      factory: params.sender.factory,
      factoryData: params.sender.factoryData,
    };
  }

  addInitCode() {
    return Object.assign(this, this.initCode);
  }

  hash() {
    return super.hash(this.context.entrypoint, this.context.chainId);
  }
}

module.exports = {
  ERC4337Helper,
};
