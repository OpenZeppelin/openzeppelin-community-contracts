const assert = require('assert');
const Conf = require('conf');
const pLimit = require('p-limit');
const prompts = require('prompts');

function confirm(message = 'Confirm') {
  return prompts({ type: 'confirm', name: 'confirm', message }).then(({ confirm }) => confirm);
}

class AsyncConf extends Conf {
  constructor(conf) {
    super(conf);
    this.limit = pLimit(1);
  }

  get(key) {
    return this.limit(() => super.get(key));
  }

  set(key, value) {
    return this.limit(() => super.set(key, value));
  }

  async getFallback(key, fallback) {
    const value = (await this.get(key)) || (await fallback());
    await this.set(key, value);
    return value;
  }

  async expect(key, value) {
    const fromCache = await this.get(key);
    if (fromCache) {
      assert.deepStrictEqual(value, fromCache);
      return false;
    } else {
      await this.set(key, value);
      return true;
    }
  }
}

class MigrationManager {
  constructor(provider, config = {}) {
    this.provider = provider;
    this.config = config;

    this.cacheAsPromise = provider.getNetwork().then(({ chainId }) => {
      this.cache = new AsyncConf({ cwd: config.cwd ?? '.', configName: `.cache-${chainId}` });
      return this.cache;
    });
  }

  ready() {
    return Promise.all([this.cacheAsPromise]).then(() => this);
  }

  migrate(key, factoryPromise, args = [], opts = {}) {
    if (!Array.isArray(args)) {
      opts = args;
      args = [];
    }
    return (
      this.ready()
        .then(() => opts.noCache && (this.cache.delete(key) || this.cache.delete(`${key}-pending`)))
        .then(
          () =>
            opts.noConfirm ||
            this.cache
              .get(key)
              .then(
                value => !!value || confirm(`Deploy "${key}" with params:\n${JSON.stringify(args, null, 4)}\nConfirm`),
              ),
        )
        // fetchOrDeploy
        .then(deploy =>
          deploy
            ? Promise.resolve(factoryPromise).then(factory =>
                this.resumeOrDeploy(key, () => factory.deploy(...args)).then(address => factory.attach(address)),
              )
            : undefined,
        )
    );
  }

  async resumeOrDeploy(key, deploy) {
    let txHash = await this.cache.get(`${key}-pending`);
    let address = await this.cache.get(key);

    if (!txHash && !address) {
      const contract = await deploy();
      txHash = contract.deploymentTransaction()?.hash;
      await this.cache.set(`${key}-pending`, txHash);
      await contract.waitForDeployment();
      address = contract.target;
      await this.cache.set(key, address);
    } else if (!address) {
      address = await this.provider
        .getTransaction(txHash)
        .then(tx => tx.wait())
        .then(receipt => receipt.contractAddress);
      await this.cache.set(key, address);
    }
    return address;
  }
}

module.exports = MigrationManager;
