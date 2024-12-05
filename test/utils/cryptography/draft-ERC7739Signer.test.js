const { loadFixture } = require('@nomicfoundation/hardhat-network-helpers');
const { ethers } = require('hardhat');
const { shouldBehaveLikeERC7739Signer } = require('./ERC7739Signer.behavior');
const { ECDSASigner, P256Signer, RSASigner } = require('../../helpers/signers');
const { getDomain } = require('../../../lib/@openzeppelin-contracts/test/helpers/eip712');

async function fixture() {
  const ECDSA = new ECDSASigner();
  const ECDSAMock = await ethers.deployContract('ERC7739SignerECDSAMock', [ECDSA.EOA.address]);

  const P256 = new P256Signer();
  const P256Mock = await ethers.deployContract('ERC7739SignerP256Mock', [P256.publicKey.qx, P256.publicKey.qy]);

  const RSA = new RSASigner();
  const RSAMock = await ethers.deployContract('ERC7739SignerRSAMock', [RSA.publicKey.e, RSA.publicKey.n]);

  return {
    ECDSA,
    ECDSAMock,
    ECDSAMockDomain: await getDomain(ECDSAMock),
    P256,
    P256Mock,
    P256MockDomain: await getDomain(P256Mock),
    RSA,
    RSAMock,
    RSAMockDomain: await getDomain(RSAMock),
  };
}

describe('ERC7739Signer', function () {
  beforeEach(async function () {
    Object.assign(this, await loadFixture(fixture));
  });

  describe('for an ECDSA signer', function () {
    beforeEach(function () {
      this.mock = this.ECDSAMock;
      this.domain = this.ECDSAMockDomain;
      this.signTypedData = this.ECDSA.signTypedData.bind(this.ECDSA);
    });

    shouldBehaveLikeERC7739Signer();
  });

  describe('for a P256 signer', function () {
    beforeEach(function () {
      this.mock = this.P256Mock;
      this.domain = this.P256MockDomain;
      this.signTypedData = this.P256.signTypedData.bind(this.P256);
    });

    shouldBehaveLikeERC7739Signer();
  });

  describe('for an RSA signer', function () {
    beforeEach(function () {
      this.mock = this.RSAMock;
      this.domain = this.RSAMockDomain;
      this.signTypedData = this.RSA.signTypedData.bind(this.RSA);
    });

    shouldBehaveLikeERC7739Signer();
  });
});
