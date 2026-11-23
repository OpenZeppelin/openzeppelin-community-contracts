import { network } from 'hardhat';
import { expect } from 'chai';
import { anyValue } from '@nomicfoundation/hardhat-ethers-chai-matchers/withArgs';

import * as AxelarHelper from './AxelarHelper';

const connection = await network.create();
const {
  ethers,
  helpers: { chain },
  networkHelpers: { loadFixture },
} = connection;

async function fixture() {
  const [owner, sender, ...accounts] = await ethers.getSigners();

  const { axelar, gatewayA, gatewayB } = await AxelarHelper.deploy(connection, owner);

  const recipient = await ethers.deployContract('$ERC7786RecipientMock', [gatewayB]);
  const invalidRecipient = await ethers.deployContract('$ERC7786RecipientInvalidMock');

  return { owner, sender, accounts, axelar, gatewayA, gatewayB, recipient, invalidRecipient };
}

describe('AxelarGatewayAdapter', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  it('initial setup', async function () {
    await expect(this.gatewayA.gateway()).to.eventually.equal(this.axelar);
    await expect(this.gatewayA.getAxelarChain(chain.erc7930)).to.eventually.equal('local');
    await expect(this.gatewayA.getErc7930Chain('local')).to.eventually.equal(chain.erc7930);
    await expect(this.gatewayA.getRemoteGateway(chain.erc7930)).to.eventually.equal(this.gatewayB.target.toLowerCase());

    await expect(this.gatewayB.gateway()).to.eventually.equal(this.axelar);
    await expect(this.gatewayB.getAxelarChain(chain.erc7930)).to.eventually.equal('local');
    await expect(this.gatewayB.getErc7930Chain('local')).to.eventually.equal(chain.erc7930);
    await expect(this.gatewayB.getRemoteGateway(chain.erc7930)).to.eventually.equal(this.gatewayA.target.toLowerCase());
  });

  it('workflow', async function () {
    const erc7930Sender = chain.toErc7930(this.sender);
    const erc7930Recipient = chain.toErc7930(this.recipient);
    const payload = ethers.randomBytes(128);
    const attributes = [];
    const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
      ['bytes', 'bytes', 'bytes'],
      [erc7930Sender, erc7930Recipient, payload],
    );

    await expect(this.gatewayA.connect(this.sender).sendMessage(erc7930Recipient, payload, attributes))
      .to.emit(this.gatewayA, 'MessageSent')
      .withArgs(ethers.ZeroHash, erc7930Sender, erc7930Recipient, payload, 0n, attributes)
      .to.emit(this.axelar, 'ContractCall')
      .withArgs(this.gatewayA, 'local', this.gatewayB, ethers.keccak256(encoded), encoded)
      .to.emit(this.axelar, 'MessageExecuted')
      .withArgs(anyValue)
      .to.emit(this.recipient, 'MessageReceived')
      .withArgs(this.gatewayB, anyValue, erc7930Sender, payload, 0n);
  });

  it('invalid recipient - bad return value', async function () {
    await expect(
      this.gatewayA
        .connect(this.sender)
        .sendMessage(chain.toErc7930(this.invalidRecipient), ethers.randomBytes(128), []),
    ).to.be.revertedWithCustomError(this.gatewayB, 'RecipientExecutionFailed');
  });

  it('invalid recipient - EOA', async function () {
    await expect(
      this.gatewayA.connect(this.sender).sendMessage(chain.toErc7930(this.accounts[0]), ethers.randomBytes(128), []),
    ).to.be.revertedWithoutReason();
  });
});
