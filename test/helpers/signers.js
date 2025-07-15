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
  sign(digest /*: BytesLike*/) /*: { serialized: string } */ {
    assertArgument(dataLength(digest) === 32, 'invalid digest length', 'digest', digest);

    const clientDataJSON = JSON.stringify({
      type: 'webauthn.get',
      challenge: encodeBase64(digest).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', ''),
    });

    const authenticatorData = toBeHex(0n, 37); // equivalent to `hexlify(new Uint8Array(37))`

    // Regular P256 signature
    const { r, s } = super.sign(sha256(concat([authenticatorData, sha256(toUtf8Bytes(clientDataJSON))])));

    const serialized = AbiCoder.defaultAbiCoder().encode(
      ['tuple(bytes32,bytes32,uint256,uint256,bytes,string)'],
      [
        [
          r,
          s,
          clientDataJSON.indexOf('"challenge"'),
          clientDataJSON.indexOf('"type"'),
          authenticatorData,
          clientDataJSON,
        ],
      ],
    );

    return { serialized };
  }
}

module.exports = {
  ZKEmailSigningKey,
  WebAuthnSigningKey,
};
