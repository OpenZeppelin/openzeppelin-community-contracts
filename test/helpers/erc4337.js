const { ethers, entrypoint, senderCreator } = require('hardhat');
const { setCode } = require('@nomicfoundation/hardhat-network-helpers');

const { UserOperation } = require('@openzeppelin/contracts/test/helpers/erc4337');

const parseInitCode = initCode => ({
  factory: '0x' + initCode.replace(/0x/, '').slice(0, 40),
  factoryData: '0x' + initCode.replace(/0x/, '').slice(40),
});

/// Global ERC-4337 environment helper.
class ERC4337Helper {
  constructor() {
    this.envAsPromise = Promise.all([ethers.provider.getNetwork(), ethers.deployContract('Create2Mock')]).then(
      ([{ chainId }, factory]) => ({
        chainId,
        factory,
      }),
    );
  }

  async wait() {
    return (this.env = await this.envAsPromise);
  }

  async newAccount(name, extraArgs = [], params = {}) {
    const { factory, chainId } = await this.wait();

    const accountFactory = await ethers.getContractFactory(name);

    if (params.erc7702signer) {
      const delegate = await accountFactory.deploy(...extraArgs);
      const instance = await params.erc7702signer.getAddress().then(address => accountFactory.attach(address));
      return new ERC7702SmartAccount(instance, chainId, delegate);
    } else {
      const initCode = await accountFactory
        .getDeployTransaction(...extraArgs)
        .then(tx =>
          factory.interface.encodeFunctionData('$deploy', [0, params.salt ?? ethers.randomBytes(32), tx.data]),
        )
        .then(deployCode => ethers.concat([factory.target, deployCode]));
      const instance = await senderCreator.createSender
        .staticCall(initCode)
        .then(address => accountFactory.attach(address));
      return new SmartAccount(instance, chainId, initCode);
    }
  }
}

/// Represent one ERC-4337 account contract.
class SmartAccount extends ethers.BaseContract {
  constructor(instance, chainId, initCode) {
    super(instance.target, instance.interface, instance.runner, instance.deployTx);
    this.address = instance.target;
    this.chainId = chainId;
    this.initCode = initCode;
  }

  async deploy(account = this.runner) {
    const { factory: to, factoryData: data } = parseInitCode(this.initCode);
    this.deployTx = await account.sendTransaction({ to, data });
    return this;
  }

  async createUserOp(userOp = {}) {
    userOp.sender ??= this;
    userOp.nonce ??= await entrypoint.getNonce(userOp.sender, 0);
    if (ethers.isAddressable(userOp.paymaster)) {
      userOp.paymaster = await ethers.resolveAddress(userOp.paymaster);
      userOp.paymasterVerificationGasLimit ??= 100_000n;
      userOp.paymasterPostOpGasLimit ??= 100_000n;
    }
    return new UserOperationWithContext(userOp);
  }
}

class ERC7702SmartAccount extends SmartAccount {
  constructor(instance, chainId, delegate) {
    super(instance, chainId);
    this.delegate = delegate;
  }

  async deploy() {
    await ethers.provider.getCode(this.delegate).then(code => setCode(this.target, code));
    return this;
  }
}

class UserOperationWithContext extends UserOperation {
  constructor(params) {
    super(params);
    this._initCode = params.sender?.initCode;
    this._chainId = params.sender?.chainId;
  }

  addInitCode() {
    if (!this._initCode) throw new Error('No init code available for the sender of this user operation');
    return Object.assign(this, parseInitCode(this._initCode));
  }

  hash() {
    return super.hash(entrypoint, this._chainId);
  }
}

module.exports = {
  ERC4337Helper,
};
