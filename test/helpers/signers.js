const { AbiCoder, assertArgument, dataLength, toBigInt } = require('ethers');

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

module.exports = {
  ZKEmailSigningKey,
};
