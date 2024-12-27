const { ethers } = require('hardhat');
const { expect } = require('chai');
const { MODULE_TYPE_VALIDATOR } = require('@openzeppelin/contracts/test/helpers/erc7579');
const { SIG_VALIDATION_SUCCESS, SIG_VALIDATION_FAILURE } = require('@openzeppelin/contracts/test/helpers/erc4337');

function shouldBehaveLikeERC7579Validator() {
  describe('isModuleType', function () {
    it('should support validator type', async function () {
      await expect(this.mock.isModuleType(MODULE_TYPE_VALIDATOR)).to.eventually.equal(true);
    });
  });

  describe('validateUserOp', function () {
    it('should return SIG_VALIDATION_SUCCESS if the signature is valid', async function () {
      // empty operation (does nothing)
      const operation = await this.account.createUserOp({}).then(op => this.signUserOp(op));
      await expect(this.mock.validateUserOp(operation.packed, operation.hash(), 0)).to.eventually.eq(
        SIG_VALIDATION_SUCCESS,
      );
    });

    it('should return SIG_VALIDATION_FAILURE if the signature is invalid', async function () {
      // empty operation (does nothing)
      const operation = await this.account.createUserOp({});
      operation.signature = '0x00';

      await expect(this.mock.validateUserOp(operation.packed, operation.hash(), 0)).to.eventually.eq(
        SIG_VALIDATION_FAILURE,
      );
    });
  });

  describe('isValidSignatureWithSender', function () {
    it('returns 0x1626ba7e if the signature is valid', async function () {
      const message = 'hello world';
      const signature = await this.signer.signMessage(message);
      const hash = ethers.hashMessage(message);

      await expect(this.mock.isValidSignatureWithSender(this.account, hash, signature)).to.eventually.equal(
        '0x1626ba7e',
      );
    });

    it('returns 0xffffffff if the signature is invalid', async function () {
      const message = 'hello world';
      const signature = '0x00';
      const hash = ethers.hashMessage(message);

      await expect(this.mock.isValidSignatureWithSender(this.account, hash, signature)).to.eventually.equal(
        '0xffffffff',
      );
    });
  });
}

module.exports = {
  shouldBehaveLikeERC7579Validator,
};
