const { ethers } = require('hardhat');
const { setCode } = require('@nomicfoundation/hardhat-network-helpers');

const { UserOperation } = require('@openzeppelin/contracts/test/helpers/erc4337');
const { deployEntrypoint } = require('@openzeppelin/contracts/test/helpers/erc4337-entrypoint');

const parseInitCode = initCode => ({
  factory: '0x' + initCode.replace(/0x/, '').slice(0, 40),
  factoryData: '0x' + initCode.replace(/0x/, '').slice(40),
});

/// Global ERC-4337 environment helper.
class ERC4337Helper {
  constructor() {
    this.cache = new Map();
    this.envAsPromise = Promise.all([
      deployEntrypoint(),
      ethers.provider.getNetwork(),
      ethers.deployContract('Create2Mock'),
    ]).then(([{ entrypoint, sendercreator }, { chainId }, factory]) => ({
      entrypoint,
      sendercreator,
      chainId,
      factory,
    }));
  }

  async wait() {
    Object.assign(this, await this.envAsPromise);
    return this;
  }

  async newAccount(name, extraArgs = [], params = {}) {
    const { factory, sendercreator } = await this.wait();

    if (!this.cache.has(name)) {
      await ethers.getContractFactory(name).then(factory => this.cache.set(name, factory));
    }
    const accountFactory = this.cache.get(name);

    if (params.erc7702signer) {
      const delegate = await accountFactory.deploy(...extraArgs);
      const instance = await params.erc7702signer.getAddress().then(address => accountFactory.attach(address));

      return new ERC7702SmartAccount(instance, delegate, this);
    } else {
      const initCode = await accountFactory
        .getDeployTransaction(...extraArgs)
        .then(tx =>
          factory.interface.encodeFunctionData('$deploy', [0, params.salt ?? ethers.randomBytes(32), tx.data]),
        )
        .then(deployCode => ethers.concat([factory.target, deployCode]));
      const instance = await sendercreator.createSender
        .staticCall(initCode)
        .then(address => accountFactory.attach(address));
      return new SmartAccount(instance, initCode, this);
    }
  }
}

/// Represent one ERC-4337 account contract.
class SmartAccount extends ethers.BaseContract {
  constructor(instance, initCode, env) {
    super(instance.target, instance.interface, instance.runner, instance.deployTx);
    this.address = instance.target;
    this.initCode = initCode;
    this.env = env;
  }

  async deploy(account = this.runner) {
    const { factory: to, factoryData: data } = parseInitCode(this.initCode);
    this.deployTx = await account.sendTransaction({ to, data });
    return this;
  }

  async createOp(args = {}) {
    const params = Object.assign({ sender: this }, args);
    // fetch nonce
    if (!params.nonce) {
      params.nonce = await this.env.entrypoint.getNonce(this, 0);
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

class ERC7702SmartAccount extends ethers.BaseContract {
  constructor(instance, delegate, env) {
    super(instance.target, instance.interface, instance.runner, instance.deployTx);
    this.address = instance.target;
    this.delegate = delegate;
    this.env = env;
  }

  async deploy() {
    await ethers.provider.getCode(this.delegate).then(code => setCode(this.target, code));
    return this;
  }

  async createOp(args = {}) {
    const params = Object.assign({ sender: this }, args);
    // fetch nonce
    if (!params.nonce) {
      params.nonce = await this.env.entrypoint.getNonce(this, 0);
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
    this.params = params;
  }

  addInitCode() {
    const { initCode } = this.params.sender;
    if (!initCode) throw new Error('No init code available for the sender of this user operation');
    return Object.assign(this, parseInitCode(initCode));
  }

  hash() {
    const { entrypoint, chainId } = this.params.sender.env;
    return super.hash(entrypoint, chainId);
  }
}

module.exports = {
  ERC4337Helper,
};
