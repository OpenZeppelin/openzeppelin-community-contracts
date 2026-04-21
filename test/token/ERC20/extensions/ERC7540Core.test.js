const { ethers } = require('hardhat');
const { expect } = require('chai');

const name = 'Vault Shares';
const symbol = 'vSHR';
const tokenName = 'Asset Token';
const tokenSymbol = 'AST';

describe('ERC7540Core', function () {
  it('construction fails if no async mechanism is enabled', async function () {
    const token = await ethers.deployContract('$ERC20', [tokenName, tokenSymbol]);
    const factory = await ethers.getContractFactory('$ERC7540');

    await expect(ethers.deployContract('$ERC7540', [name, symbol, token])).to.be.revertedWithCustomError(
      factory,
      'ERC7540MissingAsync',
    );
  });
});
