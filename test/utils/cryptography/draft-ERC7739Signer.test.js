const { ethers } = require('hardhat');
const { shouldBehaveLikeERC7739Signer } = require('./ERC7739Signer.behavior');
const { NonNativeSigner, P256SigningKey, RSASigningKey } = require('../../helpers/signers');

describe('ERC7739Signer', function () {
  describe('for an ECDSA signer', function () {
    before(async function () {
      this.signer = ethers.Wallet.createRandom();
      this.mock = await ethers.deployContract('ERC7739SignerECDSAMock', [this.signer.address]);
    });

    shouldBehaveLikeERC7739Signer();
  });

  describe('for a P256 signer', function () {
    before(async function () {
      this.signer = new NonNativeSigner(P256SigningKey.random());
      this.mock = await ethers.deployContract('ERC7739SignerP256Mock', [
        this.signer.signingKey.publicKey.qx,
        this.signer.signingKey.publicKey.qy,
      ]);
    });

    shouldBehaveLikeERC7739Signer();
  });

  describe('for an RSA signer', function () {
    before(async function () {
      this.signer = new NonNativeSigner(RSASigningKey.random());
      this.mock = await ethers.deployContract('ERC7739SignerRSAMock', [
        this.signer.signingKey.publicKey.e,
        this.signer.signingKey.publicKey.n,
      ]);
    });

    shouldBehaveLikeERC7739Signer();
  });
});
