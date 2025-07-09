const { P256SigningKey } = require('@openzeppelin/contracts/test/helpers/signers');
const {
  AbiCoder,
  assertArgument,
  concat,
  dataLength,
  sha256,
  toBeHex,
  toBigInt,
  encodeBase64,
  toUtf8Bytes,
} = require('ethers');
const { secp256r1 } = require('@noble/curves/p256');

class ZKEmailSigningKey {
  #domainName;
  #publicKeyHash;
  #emailNullifier;
  #accountSalt;
  #templateId;

  constructor(domainName, publicKeyHash, emailNullifier, accountSalt, templateId) {
    this.#domainName = domainName;
    this.#publicKeyHash = publicKeyHash;
    this.#emailNullifier = emailNullifier;
    this.#accountSalt = accountSalt;
    this.#templateId = templateId;
    this.SIGN_HASH_COMMAND = 'signHash';
  }

  get domainName() {
    return this.#domainName;
  }

  get publicKeyHash() {
    return this.#publicKeyHash;
  }

  get emailNullifier() {
    return this.#emailNullifier;
  }

  get accountSalt() {
    return this.#accountSalt;
  }

  sign(digest /*: BytesLike*/ /*: Signature*/) {
    assertArgument(dataLength(digest) === 32, 'invalid digest length', 'digest', digest);

    const timestamp = Math.floor(Date.now() / 1000);
    const command = this.SIGN_HASH_COMMAND + ' ' + toBigInt(digest).toString();
    const isCodeExist = true;
    const proof = '0x01'; // Mocked in ZKEmailVerifierMock

    // Encode the email auth message as the signature
    return {
      serialized: AbiCoder.defaultAbiCoder().encode(
        ['tuple(uint256,bytes[],uint256,tuple(string,bytes32,uint256,string,bytes32,bytes32,bool,bytes))'],
        [
          [
            this.#templateId,
            [digest],
            0, // skippedCommandPrefix
            [
              this.#domainName,
              this.#publicKeyHash,
              timestamp,
              command,
              this.#emailNullifier,
              this.#accountSalt,
              isCodeExist,
              proof,
            ],
          ],
        ],
      ),
    };
  }
}

class WebAuthnSigningKey extends P256SigningKey {
  constructor(privateKey) {
    super(privateKey);
  }

  static random() {
    return new this(secp256r1.utils.randomPrivateKey());
  }

  get PREFIX() {
    return '{"type":"webauthn.get","challenge":"';
  }

  get SUFFIX() {
    return '"}';
  }

  base64toBase64Url = str => str.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');

  sign(digest /*: BytesLike*/) /*: { serialized: string } */ {
    assertArgument(dataLength(digest) === 32, 'invalid digest length', 'digest', digest);

    const clientDataJSON = this.PREFIX.concat(this.base64toBase64Url(encodeBase64(toBeHex(digest, 32)))).concat(
      this.SUFFIX,
    );

    const authenticatorData = toBeHex('0', 37);

    // Regular P256 signature
    const sig = super.sign(sha256(concat([authenticatorData, sha256(toUtf8Bytes(clientDataJSON))])));

    return {
      serialized: this.serialize(sig.r, sig.s, authenticatorData, clientDataJSON),
    };
  }

  serialize(r, s, authenticatorData, clientDataJSON) {
    return AbiCoder.defaultAbiCoder().encode(
      ['tuple(bytes32,bytes32,uint256,uint256,bytes,string)'],
      [[r, s, 23, 1, authenticatorData, clientDataJSON]],
    );
  }
}

module.exports = {
  ZKEmailSigningKey,
  WebAuthnSigningKey,
};
