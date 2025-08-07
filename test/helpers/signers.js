const { P256SigningKey } = require('@openzeppelin/contracts/test/helpers/signers');
const {
  AbiCoder,
  ZeroHash,
  assertArgument,
  concat,
  dataLength,
  sha256,
  solidityPacked,
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

    // Create valid Groth16 proof that matches ZKEmailGroth16VerifierMock expectations
    const pA = [1n, 2n];
    const pB = [
      [3n, 4n],
      [5n, 6n],
    ];
    const pC = [7n, 8n];
    const validProof = AbiCoder.defaultAbiCoder().encode(['uint256[2]', 'uint256[2][2]', 'uint256[2]'], [pA, pB, pC]);

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
              validProof,
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

    // Flags 0x05 = AUTH_DATA_FLAGS_UP | AUTH_DATA_FLAGS_UV
    const authenticatorData = solidityPacked(['bytes32', 'bytes1', 'bytes4'], [ZeroHash, '0x05', '0x00000000']);

    // Regular P256 signature
    const { r, s } = super.sign(sha256(concat([authenticatorData, sha256(toUtf8Bytes(clientDataJSON))])));

    const serialized = AbiCoder.defaultAbiCoder().encode(
      ['bytes32', 'bytes32', 'uint256', 'uint256', 'bytes', 'string'],
      [
        r,
        s,
        clientDataJSON.indexOf('"challenge"'),
        clientDataJSON.indexOf('"type"'),
        authenticatorData,
        clientDataJSON,
      ],
    );

    return { serialized };
  }
}

module.exports = {
  ZKEmailSigningKey,
  WebAuthnSigningKey,
};
