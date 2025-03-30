const { ethers, entrypoint } = require('hardhat');
const { expect } = require('chai');
const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { anyValue } = require('@nomicfoundation/hardhat-chai-matchers/withArgs');

const { getDomain } = require('@openzeppelin/contracts/test/helpers/eip712');
const { encodeBatch, encodeMode, CALL_TYPE_BATCH } = require('@openzeppelin/contracts/test/helpers/erc7579');
const { formatType } = require('@openzeppelin/contracts/test/helpers/eip712-types');
const { PackedUserOperation } = require('../../helpers/eip712-types');
const { ERC4337Helper } = require('../../helpers/erc4337');

const { shouldBehaveLikePaymaster } = require('./Paymaster.behavior');

const value = ethers.parseEther('1');

async function fixture() {
  // EOAs and environment
  const [admin, receiver, guarantor, other] = await ethers.getSigners();
  const target = await ethers.deployContract('CallReceiverMockExtended');
  const token = await ethers.deployContract('$ERC20Mock', ['Name', 'Symbol']);

  // signers
  const accountSigner = ethers.Wallet.createRandom();
  const oracleSigner = ethers.Wallet.createRandom();

  // ERC-4337 account
  const helper = new ERC4337Helper();
  const account = await helper.newAccount('$AccountECDSAMock', ['AccountECDSA', '1', accountSigner]);
  await account.deploy();

  // ERC-4337 paymaster
  const paymaster = await ethers.deployContract(`$PaymasterERC20Mock`, ['PaymasterERC20', '1']);
  await paymaster.$_grantRole(ethers.id('ORACLE_ROLE'), oracleSigner);
  await paymaster.$_grantRole(ethers.id('WITHDRAWER_ROLE'), admin);

  // Domains
  const entrypointDomain = await getDomain(entrypoint.v08);
  const paymasterDomain = await getDomain(paymaster);

  const signUserOp = userOp =>
    accountSigner
      .signTypedData(entrypointDomain, { PackedUserOperation }, userOp.packed)
      .then(signature => Object.assign(userOp, { signature }));

  // [0x00:0x14                      ] token                 (IERC20)
  // [0x14:0x1a                      ] validAfter            (uint48)
  // [0x1a:0x20                      ] validUntil            (uint48)
  // [0x20:0x40                      ] tokenPrice            (uint256)
  // [0x40:0x54                      ] oracle                (address)
  // [0x54:0x68                      ] guarantor             (address) (optional: 0 if no guarantor)
  // [0x68:0x6a                      ] oracleSignatureLength (uint16)
  // [0x6a:0x6a+oracleSignatureLength] oracleSignature       (bytes)
  // [0x6a+oracleSignatureLength:    ] guarantorSignature    (bytes)
  const paymasterSignUserOp =
    oracle =>
    (
      userOp,
      { validAfter = 0n, validUntil = 0n, tokenPrice = ethers.WeiPerEther, guarantor = undefined, erc20 = token } = {},
    ) => {
      userOp.paymasterData = ethers.solidityPacked(
        ['address', 'uint48', 'uint48', 'uint256', 'address', 'address'],
        [
          erc20.target ?? erc20.address ?? erc20,
          validAfter,
          validUntil,
          tokenPrice,
          oracle.target ?? oracle.address ?? oracle,
          guarantor?.address ?? ethers.ZeroAddress,
        ],
      );
      return Promise.all([
        oracle.signTypedData(
          paymasterDomain,
          {
            TokenPrice: formatType({
              token: 'address',
              validAfter: 'uint48',
              validUntil: 'uint48',
              tokenPrice: 'uint256',
            }),
          },
          {
            token: erc20.target ?? erc20.address ?? erc20,
            validAfter,
            validUntil,
            tokenPrice,
          },
        ),
        guarantor ? guarantor.signTypedData(paymasterDomain, { PackedUserOperation }, userOp.packed) : '0x',
      ]).then(([oracleSignature, guarantorSignature]) => {
        userOp.paymasterData = ethers.concat([
          userOp.paymasterData,
          ethers.solidityPacked(
            ['uint16', 'bytes', 'bytes'],
            [ethers.getBytes(oracleSignature).length, oracleSignature, guarantorSignature],
          ),
        ]);
        return userOp;
      });
    };

  return {
    admin,
    receiver,
    guarantor,
    other,
    target,
    token,
    account,
    paymaster,
    signUserOp,
    paymasterSignUserOp: paymasterSignUserOp(oracleSigner), // sign using the correct key
    paymasterSignUserOpInvalid: paymasterSignUserOp(other), // sign using the wrong key
  };
}

describe('PaymasterERC20', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('core paymaster behavior', async function () {
    beforeEach(async function () {
      await this.token.$_mint(this.account, value);
      await this.token.$_approve(this.account, this.paymaster, ethers.MaxUint256);
    });

    shouldBehaveLikePaymaster({ timeRange: true });
  });

  describe('pays with ERC-20 tokens', function () {
    beforeEach(async function () {
      await this.paymaster.deposit({ value });
      this.userOp ??= {};
      this.userOp.paymaster = this.paymaster;
    });

    describe('success', function () {
      it('from account', async function () {
        // fund account
        await this.token.$_mint(this.account, value);
        await this.token.$_approve(this.account, this.paymaster, ethers.MaxUint256);

        this.extraCalls = [];
        this.withGuarantor = false;
        this.guarantorPays = false;
        this.tokenMovements = [
          { account: this.account, factor: -1n },
          { account: this.paymaster, factor: 1n },
        ];
      });

      it('from account, with guarantor refund', async function () {
        // fund guarantor. account has no asset to pay for at the beginning of the transaction, but will get them during execution.
        await this.token.$_mint(this.guarantor, value);
        await this.token.$_approve(this.guarantor, this.paymaster, ethers.MaxUint256);

        this.extraCalls = [
          { target: this.token, data: this.token.interface.encodeFunctionData('$_mint', [this.account.target, value]) },
          {
            target: this.token,
            data: this.token.interface.encodeFunctionData('approve', [this.paymaster.target, ethers.MaxUint256]),
          },
        ];
        this.withGuarantor = true;
        this.guarantorPays = false;
        this.tokenMovements = [
          { account: this.account, factor: -1n, offset: value },
          { account: this.guarantor, factor: 0n },
          { account: this.paymaster, factor: 1n },
        ];
      });

      it('from account, with guarantor refund (cold storage)', async function () {
        // fund guarantor and account beforeend. All balances and allowances are cold, making it the worst cas for postOp gas costs
        await this.token.$_mint(this.account, value);
        await this.token.$_mint(this.guarantor, value);
        await this.token.$_approve(this.account, this.paymaster, ethers.MaxUint256);
        await this.token.$_approve(this.guarantor, this.paymaster, ethers.MaxUint256);

        this.extraCalls = [];
        this.withGuarantor = true;
        this.guarantorPays = false;
        this.tokenMovements = [
          { account: this.account, factor: -1n },
          { account: this.guarantor, factor: 0n },
          { account: this.paymaster, factor: 1n },
        ];
      });

      it('from guarantor, when account fails to pay', async function () {
        // fund guarantor. account has no asset to pay for at the beginning of the transaction, and will not get them. guarantor ends up covering the cost.
        await this.token.$_mint(this.guarantor, value);
        await this.token.$_approve(this.guarantor, this.paymaster, ethers.MaxUint256);

        this.extraCalls = [];
        this.withGuarantor = true;
        this.guarantorPays = true;
        this.tokenMovements = [
          { account: this.account, factor: 0n },
          { account: this.guarantor, factor: -1n },
          { account: this.paymaster, factor: 1n },
        ];
      });

      afterEach(async function () {
        const signedUserOp = await this.account
          // prepare user operation, with paymaster data
          .createUserOp({
            ...this.userOp,
            callData: this.account.interface.encodeFunctionData('execute', [
              encodeMode({ callType: CALL_TYPE_BATCH }),
              encodeBatch(...this.extraCalls, {
                target: this.target,
                data: this.target.interface.encodeFunctionData('mockFunctionExtra'),
              }),
            ]),
          })
          .then(op =>
            this.paymasterSignUserOp(op, {
              tokenPrice: 2n * ethers.WeiPerEther,
              guarantor: this.withGuarantor ? this.guarantor : undefined,
            }),
          )
          .then(op => this.signUserOp(op));

        // send it to the entrypoint
        const txPromise = entrypoint.v08.handleOps([signedUserOp.packed], this.receiver);

        // check main events (target call and sponsoring)
        await expect(txPromise)
          .to.emit(this.paymaster, 'UserOperationSponsored')
          .withArgs(
            signedUserOp.hash(),
            this.account,
            this.withGuarantor ? this.guarantor.address : ethers.ZeroAddress,
            anyValue,
            2n * ethers.WeiPerEther,
            this.guarantorPays,
          )
          .to.emit(this.target, 'MockFunctionCalledExtra')
          .withArgs(this.account, 0n);

        // parse logs:
        // - get tokenAmount repaid for the paymaster event
        // - get the actual gas cost from the entrypoint event
        const { logs } = await txPromise.then(tx => tx.wait());
        const { tokenAmount } = logs.map(ev => this.paymaster.interface.parseLog(ev)).find(Boolean).args;
        const { actualGasCost } = logs.find(ev => ev.fragment?.name == 'UserOperationEvent').args;
        // check token balances moved as expected
        await expect(txPromise).to.changeTokenBalances(
          this.token,
          this.tokenMovements.map(({ account }) => account),
          this.tokenMovements.map(({ factor = 0n, offset = 0n }) => offset + tokenAmount * factor),
        );
        // check that ether moved as expected
        await expect(txPromise).to.changeEtherBalances(
          [entrypoint.v08, this.receiver],
          [-actualGasCost, actualGasCost],
        );

        // check token cost is within the expected values
        // skip gas consumption tests when running coverage (significantly affects the postOp costs)
        if (!process.env.COVERAGE) {
          expect(tokenAmount)
            .to.be.greaterThan(actualGasCost * 2n)
            .to.be.lessThan((actualGasCost * 2n * 110n) / 100n); // covers costs with no more than 10% overcost
        }
      });
    });

    describe('error cases', function () {
      it('invalid token', async function () {
        // prepare user operation, with paymaster data
        const signedUserOp = await this.account
          .createUserOp(this.userOp)
          .then(op => this.paymasterSignUserOp(op, { token: this.other })) // not a token
          .then(op => this.signUserOp(op));

        // send it to the entrypoint
        await expect(entrypoint.v08.handleOps([signedUserOp.packed], this.receiver))
          .to.be.revertedWithCustomError(entrypoint.v08, 'FailedOp')
          .withArgs(0n, 'AA34 signature error');
      });

      it('insufficient balance', async function () {
        await this.token.$_mint(this.account, 1n); // not enough
        await this.token.$_approve(this.account, this.paymaster, ethers.MaxUint256);

        // prepare user operation, with paymaster data
        const signedUserOp = await this.account
          .createUserOp(this.userOp)
          .then(op => this.paymasterSignUserOp(op))
          .then(op => this.signUserOp(op));

        // send it to the entrypoint
        await expect(entrypoint.v08.handleOps([signedUserOp.packed], this.receiver))
          .to.be.revertedWithCustomError(entrypoint.v08, 'FailedOp')
          .withArgs(0n, 'AA34 signature error');
      });

      it('insufficient approval', async function () {
        await this.token.$_mint(this.account, value);
        await this.token.$_approve(this.account, this.paymaster, 1n);

        // prepare user operation, with paymaster data
        const signedUserOp = await this.account
          .createUserOp(this.userOp)
          .then(op => this.paymasterSignUserOp(op))
          .then(op => this.signUserOp(op));

        // send it to the entrypoint
        await expect(entrypoint.v08.handleOps([signedUserOp.packed], this.receiver))
          .to.be.revertedWithCustomError(entrypoint.v08, 'FailedOp')
          .withArgs(0n, 'AA34 signature error');
      });
    });
  });

  describe('withdraw ERC-20 tokens', function () {
    beforeEach(async function () {
      await this.token.$_mint(this.paymaster, value);
    });

    it('withdraw some token', async function () {
      await expect(
        this.paymaster.connect(this.admin).withdrawTokens(this.token, this.receiver, 10n),
      ).to.changeTokenBalances(this.token, [this.paymaster, this.receiver], [-10n, 10n]);
    });

    it('withdraw all token', async function () {
      await expect(
        this.paymaster.connect(this.admin).withdrawTokens(this.token, this.receiver, ethers.MaxUint256),
      ).to.changeTokenBalances(this.token, [this.paymaster, this.receiver], [-value, value]);
    });

    it('only admin can withdraw', async function () {
      await expect(this.paymaster.connect(this.other).withdrawTokens(this.token, this.receiver, 10n)).to.be.reverted;
    });
  });
});
