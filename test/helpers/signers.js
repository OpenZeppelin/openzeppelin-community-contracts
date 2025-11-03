const { assertArgument, dataLength, toBigInt, AbiCoder } = require('ethers');

class ZKEmailSigningKey {
  #domainName;
  #publicKeyHash;
  #emailNullifier;
  #accountSalt;

  constructor(domainName, publicKeyHash, emailNullifier, accountSalt) {
    this.#domainName = domainName;
    this.#publicKeyHash = publicKeyHash;
    this.#emailNullifier = emailNullifier;
    this.#accountSalt = accountSalt;
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

    // Encode the EmailProof as the signature
    return {
      serialized: AbiCoder.defaultAbiCoder().encode(
        ['string', 'bytes32', 'uint256', 'string', 'bytes32', 'bytes32', 'bool', 'bytes'],
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
      ),
    };
  }
}

module.exports = {
  ZKEmailSigningKey,
};
