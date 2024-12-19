const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const { setBalance } = require('@nomicfoundation/hardhat-network-helpers');

const { impersonate } = require('@openzeppelin/contracts/test/helpers/account');
const { SIG_VALIDATION_SUCCESS, SIG_VALIDATION_FAILURE } = require('@openzeppelin/contracts/test/helpers/erc4337');
const {
  shouldSupportInterfaces,
} = require('@openzeppelin/contracts/test/utils/introspection/SupportsInterface.behavior');

function shouldBehaveLikeAnAccountBase() {
  describe('entryPoint', function () {
    it('should return the canonical entrypoint', async function () {
      await this.mock.deploy();
      expect(await this.mock.entryPoint()).to.equal(entrypoint);
    });
  });

  describe('validateUserOp', function () {
    beforeEach(async function () {
      await setBalance(this.mock.target, ethers.parseEther('1'));
      await this.mock.deploy();
    });

    it('should revert if the caller is not the canonical entrypoint', async function () {
      const selector = this.mock.interface.getFunction('executeUserOp').selector;
      const operation = await this.mock
        .createOp({
          callData: ethers.concat([
            selector,
            ethers.AbiCoder.defaultAbiCoder().encode(
              ['address', 'uint256', 'bytes'],
              [this.target.target, 0, this.target.interface.encodeFunctionData('mockFunctionExtra')],
            ),
          ]),
        })
        .then(op => this.signUserOp(op));

      await expect(this.mock.connect(this.other).validateUserOp(operation.packed, operation.hash(), 0))
        .to.be.revertedWithCustomError(this.mock, 'AccountUnauthorized')
        .withArgs(this.other);
    });

    describe('when the caller is the canonical entrypoint', function () {
      beforeEach(async function () {
        this.entrypointAsSigner = await impersonate(entrypoint.target);
      });

      it('should return SIG_VALIDATION_SUCCESS if the signature is valid', async function () {
        const selector = this.mock.interface.getFunction('executeUserOp').selector;
        const operation = await this.mock
          .createOp({
            callData: ethers.concat([
              selector,
              ethers.AbiCoder.defaultAbiCoder().encode(
                ['address', 'uint256', 'bytes'],
                [this.target.target, 0, this.target.interface.encodeFunctionData('mockFunctionExtra')],
              ),
            ]),
          })
          .then(op => this.signUserOp(op));

        expect(
          await this.mock
            .connect(this.entrypointAsSigner)
            .validateUserOp.staticCall(operation.packed, operation.hash(), 0),
        ).to.eq(SIG_VALIDATION_SUCCESS);
      });

      it('should return SIG_VALIDATION_FAILURE if the signature is invalid', async function () {
        const selector = this.mock.interface.getFunction('executeUserOp').selector;
        const operation = await this.mock.createOp({
          callData: ethers.concat([
            selector,
            ethers.AbiCoder.defaultAbiCoder().encode(
              ['address', 'uint256', 'bytes'],
              [this.target.target, 0, this.target.interface.encodeFunctionData('mockFunctionExtra')],
            ),
          ]),
        });

        operation.signature = '0x00';

        expect(
          await this.mock
            .connect(this.entrypointAsSigner)
            .validateUserOp.staticCall(operation.packed, operation.hash(), 0),
        ).to.eq(SIG_VALIDATION_FAILURE);
      });

      it('should pay missing account funds for execution', async function () {
        const selector = this.mock.interface.getFunction('executeUserOp').selector;
        const operation = await this.mock
          .createOp({
            callData: ethers.concat([
              selector,
              ethers.AbiCoder.defaultAbiCoder().encode(
                ['address', 'uint256', 'bytes'],
                [this.target.target, 0, this.target.interface.encodeFunctionData('mockFunctionExtra')],
              ),
            ]),
          })
          .then(op => this.signUserOp(op));

        const prevAccountBalance = await ethers.provider.getBalance(this.mock);
        const prevEntrypointBalance = await ethers.provider.getBalance(entrypoint);
        const amount = ethers.parseEther('0.1');

        const tx = await this.mock
          .connect(this.entrypointAsSigner)
          .validateUserOp(operation.packed, operation.hash(), amount);

        const receipt = await tx.wait();
        const callerFees = receipt.gasUsed * tx.gasPrice;

        expect(await ethers.provider.getBalance(this.mock)).to.equal(prevAccountBalance - amount);
        expect(await ethers.provider.getBalance(entrypoint)).to.equal(prevEntrypointBalance + amount - callerFees);
      });
    });
  });

  describe('fallback', function () {
    it('should receive ether', async function () {
      await this.mock.deploy();
      await setBalance(this.other.address, ethers.parseEther('1'));

      const prevBalance = await ethers.provider.getBalance(this.mock);
      const amount = ethers.parseEther('0.1');
      await this.other.sendTransaction({ to: this.mock, value: amount });

      expect(await ethers.provider.getBalance(this.mock)).to.equal(prevBalance + amount);
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
        [this.owner] = await ethers.getSigners();
        this.token = await ethers.deployContract('$ERC1155Mock', ['https://somedomain.com/{id}.json']);
        await this.token.$_mintBatch(this.owner, ids, values, '0x');
      });

      it('receives ERC1155 tokens from a single ID', async function () {
        await this.token.connect(this.owner).safeTransferFrom(this.owner, this.mock, ids[0], values[0], data);
        expect(await this.token.balanceOf(this.mock, ids[0])).to.equal(values[0]);
        for (let i = 1; i < ids.length; i++) {
          expect(await this.token.balanceOf(this.mock, ids[i])).to.equal(0n);
        }
      });

      it('receives ERC1155 tokens from a multiple IDs', async function () {
        expect(
          await this.token.balanceOfBatch(
            ids.map(() => this.mock),
            ids,
          ),
        ).to.deep.equal(ids.map(() => 0n));
        await this.token.connect(this.owner).safeBatchTransferFrom(this.owner, this.mock, ids, values, data);
        expect(
          await this.token.balanceOfBatch(
            ids.map(() => this.mock),
            ids,
          ),
        ).to.deep.equal(values);
      });
    });

    describe('onERC721Received', function () {
      it('receives an ERC721 token', async function () {
        const name = 'Some NFT';
        const symbol = 'SNFT';
        const tokenId = 1n;

        const [owner] = await ethers.getSigners();

        const token = await ethers.deployContract('$ERC721Mock', [name, symbol]);
        await token.$_mint(owner, tokenId);

        await token.connect(owner).safeTransferFrom(owner, this.mock, tokenId);

        expect(await token.ownerOf(tokenId)).to.equal(this.mock);
      });
    });
  });
}

function shouldBehaveLikeAnAccountBaseExecutor({ deployable = true } = {}) {
  describe('executeUserOp', function () {
    beforeEach(async function () {
      await setBalance(this.mock.target, ethers.parseEther('1'));
      expect(await ethers.provider.getCode(this.mock)).to.equal('0x');
      this.entrypointAsSigner = await impersonate(entrypoint.target);
    });

    it('should revert if the caller is not the canonical entrypoint or the account itself', async function () {
      await this.mock.deploy();

      const selector = this.mock.interface.getFunction('executeUserOp').selector;
      const operation = await this.mock
        .createOp({
          callData: ethers.concat([
            selector,
            ethers.AbiCoder.defaultAbiCoder().encode(
              ['address', 'uint256', 'bytes'],
              [this.target.target, 0, this.target.interface.encodeFunctionData('mockFunctionExtra')],
            ),
          ]),
        })
        .then(op => this.signUserOp(op));

      await expect(this.mock.connect(this.other).executeUserOp(operation.packed, operation.hash()))
        .to.be.revertedWithCustomError(this.mock, 'AccountUnauthorized')
        .withArgs(this.other);
    });

    if (deployable) {
      describe('when not deployed', function () {
        it('should be created with handleOps and increase nonce', async function () {
          const selector = this.mock.interface.getFunction('executeUserOp').selector;
          const operation = await this.mock
            .createOp({
              callData: ethers.concat([
                selector,
                ethers.AbiCoder.defaultAbiCoder().encode(
                  ['address', 'uint256', 'bytes'],
                  [this.target.target, 17, this.target.interface.encodeFunctionData('mockFunctionExtra')],
                ),
              ]),
            })
            .then(op => op.addInitCode())
            .then(op => this.signUserOp(op));

          await expect(entrypoint.handleOps([operation.packed], this.beneficiary))
            .to.emit(entrypoint, 'AccountDeployed')
            .withArgs(operation.hash(), this.mock, this.factory, ethers.ZeroAddress)
            .to.emit(this.target, 'MockFunctionCalledExtra')
            .withArgs(this.mock, 17);
          expect(await this.mock.getNonce()).to.equal(1);
        });

        it('should revert if the signature is invalid', async function () {
          const selector = this.mock.interface.getFunction('executeUserOp').selector;
          const operation = await this.mock
            .createOp({
              callData: ethers.concat([
                selector,
                ethers.AbiCoder.defaultAbiCoder().encode(
                  ['address', 'uint256', 'bytes'],
                  [this.target.target, 17, this.target.interface.encodeFunctionData('mockFunctionExtra')],
                ),
              ]),
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
        const selector = this.mock.interface.getFunction('executeUserOp').selector;
        const operation = await this.mock
          .createOp({
            callData: ethers.concat([
              selector,
              ethers.AbiCoder.defaultAbiCoder().encode(
                ['address', 'uint256', 'bytes'],
                [this.target.target, 42, this.target.interface.encodeFunctionData('mockFunctionExtra')],
              ),
            ]),
          })
          .then(op => this.signUserOp(op));

        expect(await this.mock.getNonce()).to.equal(0);
        await expect(entrypoint.handleOps([operation.packed], this.beneficiary))
          .to.emit(this.target, 'MockFunctionCalledExtra')
          .withArgs(this.mock, 42);
        expect(await this.mock.getNonce()).to.equal(1);
      });
    });
  });
}

module.exports = {
  shouldBehaveLikeAnAccountBase,
  shouldBehaveLikeAccountHolder,
  shouldBehaveLikeAnAccountBaseExecutor,
};
