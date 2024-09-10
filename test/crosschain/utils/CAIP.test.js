const { ethers } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');

const format = (...args) => args.join(':');

const SAMPLES = [].concat(
  ['1', '56', '137', '43114', '250', '1284', '1313161554', '42161', '10', '8453', '5000', '42220', '2222', '314', '59144', '2031', '534352', '13371', '252', '81457'].map(reference => ({
    namespace: 'eip155',
    reference,
    account: ethers.Wallet.createRandom().address, // random address
  })),
  [ 'axelar-dojo-1', 'osmosis-1', 'cosmoshub-4', 'juno-1', 'emoney-3', 'injective-1', 'crescent-1', 'kaiyo-1', 'secret-4', 'secret-4', 'pacific-1', 'stargaze-1', 'mantle-1', 'fetchhub-4', 'kichain-2', 'evmos_9001-2', 'xstaxy-1', 'comdex-1', 'core-1', 'regen-1', 'umee-1', 'agoric-3', 'dimension_37-1', 'acre_9052-1', 'stride-1', 'carbon-1', 'sommelier-3', 'neutron-1', 'reb_1111-1', 'archway-1', 'pio-mainnet-1', 'ixo-5', 'migaloo-1', 'teritori-1', 'haqq_11235-1', 'celestia', 'agamotto', 'chihuahua-1', 'ssc-1', 'dymension_1100-1', 'fxcore', 'perun-1', 'bitsong-2b', 'pirin-1', 'lava-mainnet-1', 'phoenix-1', 'columbus-5' ].map(reference => ({
    namespace: 'cosmos',
    reference,
    account: ethers.encodeBase58(ethers.randomBytes(32)), // random base58 string
  })),
).map(entry => Object.assign(entry, { caip2: format(entry.namespace, entry.reference), caip10: format(entry.namespace, entry.reference, entry.account) }));

async function fixture() {
  const caip2 = await ethers.deployContract('$CAIP2');
  const caip10 = await ethers.deployContract('$CAIP10');
  const { chainId } = await ethers.provider.getNetwork();
  return { caip2, caip10, chainId };
}

describe('CAIP utilities', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('CAIP-2', function () {
    it('format()', async function () {
      expect(await this.caip2.$format()).to.equal(format('eip155', this.chainId));
    });

    for (const { namespace, reference, caip2 } of SAMPLES)
      it (`format(${namespace}, ${reference})`, async function () {
        expect(await this.caip2.$format(namespace, reference)).to.equal(caip2);
      });

    for (const { namespace, reference, caip2 } of SAMPLES)
      it(`parse(${caip2})`, async function () {
        expect(await this.caip2.$parse(caip2)).to.deep.equal([ namespace, reference ]);
      });
  });

  describe('CAIP-10', function () {
    const { address: account } = ethers.Wallet.createRandom();

    it(`format(${account})`, async function () {
      // lowercase encoding for now
      expect(await this.caip10.$format(ethers.Typed.address(account))).to.equal(format('eip155', this.chainId, account.toLowerCase()));
    });

    for (const { account, caip2, caip10 } of SAMPLES)
      it (`format(${caip2}, ${account})`, async function () {
        expect(await this.caip10.$format(ethers.Typed.string(caip2), ethers.Typed.string(account))).to.equal(caip10);
      });

    for (const { account, caip2, caip10 } of SAMPLES)
      it(`parse(${caip10})`, async function () {
        expect(await this.caip10.$parse(caip10)).to.deep.equal([ caip2, account ]);
      });
  });

});
