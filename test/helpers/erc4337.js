const { setCode } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { UserOperation: UserOperationVanilla } = require('../../lib/@openzeppelin-contracts/test/helpers/erc4337');
const { PersonalSignHelper } = require('./erc7739');

const CANONICAL_ENTRYPOINT = '0x0000000071727De22E5E9d8BAf0edAc6f37da032';

/// Global ERC-4337 environment helper.
class ERC4337Helper {
  constructor(account, params = {}) {
    this.entrypointAsPromise = ethers.deployContract('EntryPoint');
    this.factoryAsPromise = ethers.deployContract('Create2Mock');
    this.accountContractAsPromise = ethers.getContractFactory(account);
    this.chainIdAsPromise = ethers.provider.getNetwork().then(({ chainId }) => chainId);
    this.senderCreatorAsPromise = ethers.deployContract('SenderCreator');
    this.params = params;
  }

  async wait() {
    const entrypoint = await this.entrypointAsPromise;
    await entrypoint.getDeployedCode().then(code => setCode(CANONICAL_ENTRYPOINT, code));
    this.entrypoint = entrypoint.attach(CANONICAL_ENTRYPOINT);
    this.entrypointAsPromise = Promise.resolve(this.entrypoint);

    this.factory = await this.factoryAsPromise;
    this.accountContract = await this.accountContractAsPromise;
    this.chainId = await this.chainIdAsPromise;
    this.senderCreator = await this.senderCreatorAsPromise;
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
    this.context = context;
  }

  async deploy(account = this.runner) {
    this.deployTx = await account.sendTransaction({
      to: '0x' + this.initCode.replace(/0x/, '').slice(0, 40),
      data: '0x' + this.initCode.replace(/0x/, '').slice(40),
    });
    return this;
  }

  async createOp(args = {}) {
    const params = Object.assign({ sender: this }, args);
    // fetch nonce
    if (!params.nonce) {
      params.nonce = await this.context.entrypointAsPromise.then(entrypoint => entrypoint.getNonce(this, 0));
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
    return new UserOperation(params);
  }
}

class UserOperation extends UserOperationVanilla {
  constructor(params) {
    super(params);
    this.context = params.sender.context;
    this.senderInitCode = params.sender.initCode;
  }

  addInitCode() {
    this.initCode = this.senderInitCode;
    return this;
  }

  async sign(domain, signer) {
    this.signature = await PersonalSignHelper.sign(
      signer.signTypedData.bind(signer),
      this.hash(this.context.entrypoint.target, this.context.chainId),
      domain,
    );

    return this;
  }
}

module.exports = {
  ERC4337Helper,
};
