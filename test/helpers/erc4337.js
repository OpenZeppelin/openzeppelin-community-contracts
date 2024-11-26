const { setCode } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');

/// Global ERC-4337 environment helper.
class ERC4337Helper {
  constructor(account, params = {}) {
    this.entrypointAsPromise = ethers.deployContract('EntryPoint');
    this.factoryAsPromise = ethers.deployContract('$Create2');
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

module.exports = {
  ERC4337Helper,
};
