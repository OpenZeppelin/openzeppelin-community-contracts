const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');
const { SIG_VALIDATION_SUCCESS, SIG_VALIDATION_FAILURE } = require('@openzeppelin/contracts/test/helpers/erc4337');
const { CALL_TYPE_BATCH, encodeMode, encodeBatch } = require('@openzeppelin/contracts/test/helpers/erc7579');
const {
  shouldSupportInterfaces,
} = require('@openzeppelin/contracts/test/utils/introspection/SupportsInterface.behavior');

function shouldBehaveLikeAccountCore() {
  describe('entryPoint', function () {
    it('should return the canonical entrypoint', async function () {
      await this.mock.deploy();
      await expect(this.mock.entryPoint()).to.eventually.equal(entrypoint);
    });
  });

  describe('validateUserOp', function () {
    beforeEach(async function () {
      await this.other.sendTransaction({ to: this.mock.target, value: ethers.parseEther('1') });
      await this.mock.deploy();
      this.userOp ??= {};
    });

    it('should revert if the caller is not the canonical entrypoint', async function () {
      // empty operation (does nothing)
      const operation = await this.mock.createUserOp(this.userOp).then(op => this.signUserOp(op));

      await expect(this.mock.connect(this.other).validateUserOp(operation.packed, operation.hash(), 0))
        .to.be.revertedWithCustomError(this.mock, 'AccountUnauthorized')
        .withArgs(this.other);
    });

    describe('when the caller is the canonical entrypoint', function () {
      beforeEach(async function () {
        this.mockFromEntrypoint = this.mock.connect(await impersonate(entrypoint.target));
      });

      it('should return SIG_VALIDATION_SUCCESS if the signature is valid', async function () {
        // empty operation (does nothing)
        const operation = await this.mock.createUserOp(this.userOp).then(op => this.signUserOp(op));

        expect(await this.mockFromEntrypoint.validateUserOp.staticCall(operation.packed, operation.hash(), 0)).to.eq(
          SIG_VALIDATION_SUCCESS,
        );
      });

      it('should return SIG_VALIDATION_FAILURE if the signature is invalid', async function () {
        // empty operation (does nothing)
        const operation = await this.mock.createUserOp(this.userOp);
        operation.signature = '0x00';

        expect(await this.mockFromEntrypoint.validateUserOp.staticCall(operation.packed, operation.hash(), 0)).to.eq(
          SIG_VALIDATION_FAILURE,
        );
      });

      it('should pay missing account funds for execution', async function () {
        // empty operation (does nothing)
        const operation = await this.mock.createUserOp(this.userOp).then(op => this.signUserOp(op));
        const value = 42n;

        await expect(
          this.mockFromEntrypoint.validateUserOp(operation.packed, operation.hash(), value),
        ).to.changeEtherBalances([this.mock, entrypoint], [-value, value]);
      });
    });
  });

  describe('fallback', function () {
    it('should receive ether', async function () {
      await this.mock.deploy();
      const value = 42n;

      await expect(this.other.sendTransaction({ to: this.mock, value })).to.changeEtherBalances(
        [this.other, this.mock],
        [-value, value],
      );
    });
  });
}

function shouldBehaveLikeAccountHolder() {
  describe('onReceived', function () {
    beforeEach(async function () {
      await this.mock.deploy();
    });

    shouldSupportInterfaces(['ERC1155Receiver']);

    describe('onERC1155Received', function () {
      const ids = [1n, 2n, 3n];
      const values = [1000n, 2000n, 3000n];
      const data = '0x12345678';

      beforeEach(async function () {
        this.token = await ethers.deployContract('$ERC1155Mock', ['https://somedomain.com/{id}.json']);
        await this.token.$_mintBatch(this.other, ids, values, '0x');
      });

      it('receives ERC1155 tokens from a single ID', async function () {
        await this.token.connect(this.other).safeTransferFrom(this.other, this.mock, ids[0], values[0], data);

        await expect(
          this.token.balanceOfBatch(
            ids.map(() => this.mock),
            ids,
          ),
        ).to.eventually.deep.equal(values.map((v, i) => (i == 0 ? v : 0n)));
      });

      it('receives ERC1155 tokens from a multiple IDs', async function () {
        await expect(
          this.token.balanceOfBatch(
            ids.map(() => this.mock),
            ids,
          ),
        ).to.eventually.deep.equal(ids.map(() => 0n));

        await this.token.connect(this.other).safeBatchTransferFrom(this.other, this.mock, ids, values, data);
        await expect(
          this.token.balanceOfBatch(
            ids.map(() => this.mock),
            ids,
          ),
        ).to.eventually.deep.equal(values);
      });
    });

    describe('onERC721Received', function () {
      const tokenId = 1n;

      beforeEach(async function () {
        this.token = await ethers.deployContract('$ERC721Mock', ['Some NFT', 'SNFT']);
        await this.token.$_mint(this.other, tokenId);
      });

      it('receives an ERC721 token', async function () {
        await this.token.connect(this.other).safeTransferFrom(this.other, this.mock, tokenId);

        await expect(this.token.ownerOf(tokenId)).to.eventually.equal(this.mock);
      });
    });
  });
}

function shouldBehaveLikeAccountERC7821({ deployable = true } = {}) {
  describe('execute', function () {
    beforeEach(async function () {
      // give eth to the account (before deployment)
      await this.other.sendTransaction({ to: this.mock.target, value: ethers.parseEther('1') });

      // account is not initially deployed
      await expect(ethers.provider.getCode(this.mock)).to.eventually.equal('0x');

      this.encodeUserOpCalldata = (...calls) =>
        this.mock.interface.encodeFunctionData('execute', [
          encodeMode({ callType: CALL_TYPE_BATCH }),
          encodeBatch(...calls),
        ]);
    });

    it('should revert if the caller is not the canonical entrypoint or the account itself', async function () {
      await this.mock.deploy();

      await expect(
        this.mock.connect(this.other).execute(
          encodeMode({ callType: CALL_TYPE_BATCH }),
          encodeBatch({
            target: this.target,
            data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
          }),
        ),
      )
        .to.be.revertedWithCustomError(this.mock, 'AccountUnauthorized')
        .withArgs(this.other);
    });

    if (deployable) {
      describe('when not deployed', function () {
        it('should be created with handleOps and increase nonce', async function () {
          const operation = await this.mock
            .createUserOp({
              callData: this.encodeUserOpCalldata({
                target: this.target,
                value: 17,
                data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
              }),
            })
            .then(op => op.addInitCode())
            .then(op => this.signUserOp(op));

          // Can't call the account to get its nonce before it's deployed
          await expect(entrypoint.getNonce(this.mock.target, 0)).to.eventually.equal(0);
          await expect(entrypoint.handleOps([operation.packed], this.beneficiary))
            .to.emit(entrypoint, 'AccountDeployed')
            .withArgs(operation.hash(), this.mock, this.factory, ethers.ZeroAddress)
            .to.emit(this.target, 'MockFunctionCalledExtra')
            .withArgs(this.mock, 17);
          await expect(this.mock.getNonce()).to.eventually.equal(1);
        });

        it('should revert if the signature is invalid', async function () {
          const operation = await this.mock
            .createUserOp({
              callData: this.encodeUserOpCalldata({
                target: this.target,
                value: 17,
                data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
              }),
            })
            .then(op => op.addInitCode());

          operation.signature = '0x00';

          await expect(entrypoint.handleOps([operation.packed], this.beneficiary)).to.be.reverted;
        });
      });
    }

    describe('when deployed', function () {
      beforeEach(async function () {
        await this.mock.deploy();
      });

      it('should increase nonce and call target', async function () {
        const operation = await this.mock
          .createUserOp({
            callData: this.encodeUserOpCalldata({
              target: this.target,
              value: 42,
              data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
            }),
          })
          .then(op => this.signUserOp(op));

        await expect(this.mock.getNonce()).to.eventually.equal(0);
        await expect(entrypoint.handleOps([operation.packed], this.beneficiary))
          .to.emit(this.target, 'MockFunctionCalledExtra')
          .withArgs(this.mock, 42);
        await expect(this.mock.getNonce()).to.eventually.equal(1);
      });

      it('should support sending eth to an EOA', async function () {
        const operation = await this.mock
          .createUserOp({ callData: this.encodeUserOpCalldata({ target: this.other, value: 42 }) })
          .then(op => this.signUserOp(op));

        await expect(this.mock.getNonce()).to.eventually.equal(0);
        await expect(entrypoint.handleOps([operation.packed], this.beneficiary)).to.changeEtherBalance(this.other, 42);
        await expect(this.mock.getNonce()).to.eventually.equal(1);
      });

      it('should support batch execution', async function () {
        const value1 = 43374337n;
        const value2 = 69420n;

        const operation = await this.mock
          .createUserOp({
            callData: this.encodeUserOpCalldata(
              { target: this.other, value: value1 },
              {
                target: this.target,
                value: value2,
                data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
              },
            ),
          })
          .then(op => this.signUserOp(op));

        await expect(this.mock.getNonce()).to.eventually.equal(0);
        const tx = entrypoint.handleOps([operation.packed], this.beneficiary);
        await expect(tx).to.changeEtherBalances([this.other, this.target], [value1, value2]);
        await expect(tx).to.emit(this.target, 'MockFunctionCalledExtra').withArgs(this.mock, value2);
        await expect(this.mock.getNonce()).to.eventually.equal(1);
      });
    });
  });
}

module.exports = {
  shouldBehaveLikeAccountCore,
  shouldBehaveLikeAccountHolder,
  shouldBehaveLikeAccountERC7821,
};
