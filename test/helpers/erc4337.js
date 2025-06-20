const { ethers, config, entrypoint, senderCreator } = require('hardhat');

const { UserOperation } = require('@openzeppelin/contracts/test/helpers/erc4337');

const parseInitCode = initCode => ({
  factory: '0x' + initCode.replace(/0x/, '').slice(0, 40),
  factoryData: '0x' + initCode.replace(/0x/, '').slice(40),
});

/// Global ERC-4337 environment helper.
class ERC4337Helper {
  constructor() {
    this.factoryAsPromise = ethers.deployContract('$Create2');
  }

  async wait() {
    this.factory = await this.factoryAsPromise;
    return this;
  }

  async newAccount(name, extraArgs = [], params = {}) {
    const env = {
      entrypoint: params.entrypoint ?? entrypoint.v08,
      senderCreator: params.senderCreator ?? senderCreator.v08,
    };

    const { factory } = await this.wait();

    const accountFactory = await ethers.getContractFactory(name);

    if (params.erc7702signer) {
      const delegate = await accountFactory.deploy(...extraArgs);
      const instance = await params.erc7702signer.getAddress().then(address => accountFactory.attach(address));
      const authorization = await params.erc7702signer.authorize({ address: delegate.target });
      return new ERC7702SmartAccount(instance, authorization, env);
    } else {
      const initCode = await accountFactory
        .getDeployTransaction(...extraArgs)
        .then(tx =>
          factory.interface.encodeFunctionData('$deploy', [0, params.salt ?? ethers.randomBytes(32), tx.data]),
        )
        .then(deployCode => ethers.concat([factory.target, deployCode]));

      const instance = await ethers.provider
        .call({
          from: env.entrypoint,
          to: env.senderCreator,
          data: env.senderCreator.interface.encodeFunctionData('createSender', [initCode]),
        })
        .then(result => ethers.getAddress(ethers.hexlify(ethers.getBytes(result).slice(-20))))
        .then(address => accountFactory.attach(address));

      return new SmartAccount(instance, initCode, env);
    }
  }
}

/// Represent one ERC-4337 account contract.
class SmartAccount extends ethers.BaseContract {
  constructor(instance, initCode, env) {
    super(instance.target, instance.interface, instance.runner, instance.deployTx);
    this.address = instance.target;
    this.initCode = initCode;
    this._env = env;
  }

  async deploy(account = this.runner) {
    const { factory: to, factoryData: data } = parseInitCode(this.initCode);
    this.deployTx = await account.sendTransaction({ to, data });
    return this;
  }

  async createUserOp(userOp = {}) {
    userOp.sender ??= this;
    userOp.nonce ??= await this._env.entrypoint.getNonce(userOp.sender, 0);
    if (ethers.isAddressable(userOp.paymaster)) {
      userOp.paymaster = await ethers.resolveAddress(userOp.paymaster);
      userOp.paymasterVerificationGasLimit ??= 100_000n;
      userOp.paymasterPostOpGasLimit ??= 100_000n;
    }
    return new UserOperationWithContext(userOp, this._env);
  }
}

class ERC7702SmartAccount extends SmartAccount {
  constructor(instance, authorization, env) {
    super(instance, undefined, env);
    this.authorization = authorization;
  }

  async deploy() {
    // hardhat signers from @nomicfoundation/hardhat-ethers do not support type 4 txs.
    // so we rebuild it using "native" ethers
    await ethers.Wallet.fromPhrase(config.networks.hardhat.accounts.mnemonic, ethers.provider).sendTransaction({
      to: ethers.ZeroAddress,
      authorizationList: [this.authorization],
      gasLimit: 46_000n, // 21,000 base + PER_EMPTY_ACCOUNT_COST
    });

    return this;
  }
}

class UserOperationWithContext extends UserOperation {
  constructor(userOp, env) {
    super(userOp);
    this._sender = userOp.sender;
    this._env = env;
  }

  addInitCode() {
    if (this._sender?.initCode) {
      return Object.assign(this, parseInitCode(this._sender.initCode));
    } else throw new Error('No init code available for the sender of this user operation');
  }

  getAuthorization() {
    if (this._sender?.authorization) {
      return this._sender.authorization;
    } else throw new Error('No EIP-7702 authorization available for the sender of this user operation');
  }

  hash() {
    return super.hash(this._env.entrypoint);
  }
}

module.exports = {
  ERC4337Helper,
};
