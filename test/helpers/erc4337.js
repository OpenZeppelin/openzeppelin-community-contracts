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
    return (this.env = await this.envAsPromise);
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

  async fillUserOp(userOp) {
    if (!userOp.nonce) {
      const { entrypoint } = await this.wait();
      userOp.nonce = await entrypoint.getNonce(userOp.sender, 0);
    }
    if (ethers.isAddressable(userOp.paymaster)) {
      userOp.paymaster = await ethers.resolveAddress(userOp.paymaster);
      userOp.paymasterVerificationGasLimit ??= 100_000n;
      userOp.paymasterPostOpGasLimit ??= 100_000n;
      userOp.paymasterAndData = ethers.solidityPacked(
        ['address', 'uint128', 'uint128'],
        [userOp.paymaster, userOp.paymasterVerificationGasLimit, userOp.paymasterPostOpGasLimit],
      );
    }
    return userOp;
  }
}

/// Represent one ERC-4337 account contract.
class SmartAccount extends ethers.BaseContract {
  constructor(instance, initCode, helper) {
    super(instance.target, instance.interface, instance.runner, instance.deployTx);
    this.address = instance.target;
    this.initCode = initCode;
    this.helper = helper;
  }

  async deploy(account = this.runner) {
    const { factory: to, factoryData: data } = parseInitCode(this.initCode);
    this.deployTx = await account.sendTransaction({ to, data });
    return this;
  }

  createOp(userOp = {}) {
    return this.helper
      .fillUserOp({ sender: this, ...userOp })
      .then(filledUserOp => new UserOperationWithContext(filledUserOp));
  }
}

class ERC7702SmartAccount extends ethers.BaseContract {
  constructor(instance, delegate, helper) {
    super(instance.target, instance.interface, instance.runner, instance.deployTx);
    this.address = instance.target;
    this.delegate = delegate;
    this.helper = helper;
  }

  async deploy() {
    await ethers.provider.getCode(this.delegate).then(code => setCode(this.target, code));
    return this;
  }

  createOp(userOp = {}) {
    return this.helper
      .fillUserOp({ sender: this, ...userOp })
      .then(filledUserOp => new UserOperationWithContext(filledUserOp));
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
    const { entrypoint, chainId } = this.params.sender.helper.env;
    return super.hash(entrypoint, chainId);
  }
}

module.exports = {
  ERC4337Helper,
};
