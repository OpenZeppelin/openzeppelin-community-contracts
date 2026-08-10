const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { getDomain, domainSeparator } = require('@openzeppelin/contracts/test/helpers/eip712');

const VARIABLE_RATE_FLAG = 0x01n;
const FLASH_MINT_FLAG = 0x02n;

const tokenName = 'Asset Token';
const tokenSymbol = 'AST';
const configs = [
  { description: 'fixed rate wrapper', args: [false, false] },
  { description: 'variable rate wrapper', args: [true, false] },
  { description: 'flash mintable wrapper', args: [false, true] },
];

async function fixture() {
  const [holder, other] = await ethers.getSigners();

  const token = await ethers.deployContract('$ERC20', [tokenName, tokenSymbol]);
  const otherToken = await ethers.deployContract('$ERC20', ['Other Token', 'OTH']);
  const factory = await ethers.deployContract('ERC20UniversalWrapperFactory');
  const implementation = await factory
    .implementation()
    .then(address => ethers.getContractAt('ERC20UniversalWrapper', address));

  return { holder, other, token, otherToken, factory, implementation };
}

describe('ERC20UniversalWrapperFactory', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('implementation', function () {
    it('is deployed along with the factory', async function () {
      await expect(ethers.provider.getCode(this.implementation)).to.eventually.not.equal('0x');
    });

    it('cannot be used directly, as it has no immutable args', async function () {
      await expect(this.implementation.asset()).to.be.revertedWithCustomError(
        this.implementation,
        'MissingImmutableArgs',
      );
      await expect(this.implementation.name()).to.be.revertedWithCustomError(
        this.implementation,
        'MissingImmutableArgs',
      );
    });
  });

  describe('predict', function () {
    it('predicted/deployment address depends on the settings', async function () {
      const allAddresses = await Promise.all(configs.map(({ args }) => this.factory.predict(this.token, ...args)));
      expect(new Set(allAddresses).size).to.equal(configs.length);
    });

    it('reverts for incompatible settings', async function () {
      await expect(this.factory.predict(this.token, true, true)).to.be.revertedWithCustomError(
        this.factory,
        'IncompatibleSettings',
      );
    });

    for (const { description, args } of configs) {
      describe(`with ${description}`, function () {
        it(`returns the address the ${description} is deployed at`, async function () {
          const predicted = await this.factory.predict(this.token, ...args);
          await expect(this.factory.deploy.staticCall(this.token, ...args)).to.eventually.equal(predicted);
        });

        it('does not deploy anything', async function () {
          const predicted = await this.factory.predict(this.token, ...args);
          await expect(ethers.provider.getCode(predicted)).to.eventually.equal('0x');
        });

        it('keeps returning the same address after deployment', async function () {
          const predicted = await this.factory.predict(this.token, ...args);
          await this.factory.deploy(this.token, ...args);
          await expect(this.factory.predict(this.token, ...args)).to.eventually.equal(predicted);
        });

        it('depends on the underlying token', async function () {
          await expect(this.factory.predict(this.token, ...args)).to.eventually.not.equal(
            await this.factory.predict(this.otherToken, ...args),
          );
        });
      });
    }
  });

  describe('deploy', function () {
    it('supports multiple configurations of the same underlying token', async function () {
      for (const { args } of configs) {
        await expect(this.factory.deploy(this.token, ...args)).to.emit(this.factory, 'ERC20UniversalWrapperDeployed');
      }
    });

    it('reverts for incompatible settings', async function () {
      await expect(this.factory.deploy(this.token, true, true)).to.be.revertedWithCustomError(
        this.factory,
        'IncompatibleSettings',
      );
    });

    for (const { description, args } of configs) {
      const [variableRate, flashMintable] = args;
      const settings = (variableRate && VARIABLE_RATE_FLAG) || (flashMintable && FLASH_MINT_FLAG) || 0n;

      describe(`with ${description}`, function () {
        it(`deploys at the predicted address, and emits an event`, async function () {
          const predicted = await this.factory.predict(this.token, ...args);

          await expect(this.factory.deploy(this.token, ...args))
            .to.emit(this.factory, 'ERC20UniversalWrapperDeployed')
            .withArgs(predicted, this.token, settings);

          await expect(ethers.provider.getCode(predicted)).to.eventually.not.equal('0x');
        });

        it('is permissionless', async function () {
          const predicted = await this.factory.predict(this.token, ...args);

          await expect(this.factory.connect(this.other).deploy(this.token, ...args))
            .to.emit(this.factory, 'ERC20UniversalWrapperDeployed')
            .withArgs(predicted, this.token, settings);
        });

        it('reverts when the same configuration is deployed twice', async function () {
          await this.factory.deploy(this.token, ...args);

          await expect(this.factory.deploy(this.token, ...args)).to.be.revertedWithCustomError(
            this.factory,
            'FailedDeployment',
          );
        });
      });
    }
  });

  describe('deployed wrapper', function () {
    for (const { description, args } of configs) {
      const [variableRate, flashMintable] = args;

      describe(description, function () {
        beforeEach(async function () {
          await this.factory.deploy(this.token, ...args);
          this.wrapper = await this.factory
            .predict(this.token, ...args)
            .then(address => ethers.getContractAt('ERC20UniversalWrapper', address));
        });

        it('is configured with the underlying token', async function () {
          await expect(this.wrapper.asset()).to.eventually.equal(this.token);
        });

        it('derives its metadata from the underlying token', async function () {
          await expect(this.wrapper.name()).to.eventually.equal(`Wrapped ${tokenName}`);
          await expect(this.wrapper.symbol()).to.eventually.equal(`w${tokenSymbol}`);
          await expect(this.wrapper.decimals()).to.eventually.equal(await this.token.decimals());
        });

        it(`${flashMintable ? 'enables' : 'disables'} flash minting`, async function () {
          const currentSupply = await this.wrapper.totalSupply();

          await expect(this.wrapper.maxFlashLoan(this.wrapper)).to.eventually.equal(
            flashMintable ? ethers.MaxUint256 - currentSupply : 0n,
          );
          // never a flash lender for any other token
          await expect(this.wrapper.maxFlashLoan(this.token)).to.eventually.equal(0n);
        });

        describe('exchange rate', function () {
          beforeEach(async function () {
            // deposit
            const deposited = 17n;
            await this.token.$_mint(this.holder, deposited);
            await this.token.connect(this.holder).approve(this.wrapper, deposited);
            await this.wrapper.connect(this.holder).deposit(deposited, this.holder);
            // donation
            const donated = 42n;
            await this.token.$_mint(this.wrapper, donated);
          });

          it(`is ${variableRate ? 'variable' : 'fixed to 1:1'}`, async function () {
            const amount = ethers.WeiPerEther;
            if (variableRate) {
              await expect(this.wrapper.convertToAssets(amount)).to.eventually.be.greaterThan(amount);
              await expect(this.wrapper.convertToShares(amount)).to.eventually.be.lessThan(amount);
            } else {
              await expect(this.wrapper.convertToAssets(amount)).to.eventually.equal(amount);
              await expect(this.wrapper.convertToShares(amount)).to.eventually.equal(amount);
            }
          });
        });

        it('EIP-712 domain is correct', async function () {
          const expectedDomain = await ethers.provider.getNetwork().then(({ chainId }) => ({
            name: `Wrapped ${tokenName}`,
            version: '1',
            chainId,
            verifyingContract: this.wrapper.target,
          }));

          await expect(getDomain(this.wrapper)).to.eventually.deep.equal(expectedDomain);
          await expect(this.wrapper.DOMAIN_SEPARATOR()).to.eventually.equal(domainSeparator(expectedDomain));
        });
      });
    }
  });
});
