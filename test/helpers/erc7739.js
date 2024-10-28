const { ethers } = require('hardhat');
const { domainType, formatType } = require('./eip712');

class PersonalSignHelper {
  static types = { PersonalSign: formatType({ prefixed: 'bytes' }) };

  static prepare(message) {
    return {
      prefixed: ethers.concat([
        ethers.toUtf8Bytes(ethers.MessagePrefix),
        ethers.toUtf8Bytes(String(message.length)),
        typeof message === 'string' ? ethers.toUtf8Bytes(message) : message,
      ]),
    };
  }

  static hash(message) {
    return message.prefixed ? ethers.keccak256(message.prefixed) : ethers.hashMessage(message);
  }

  static sign(signTypedData, data, signerDomain) {
    return signTypedData(signerDomain, this.types, data.prefixed ? data : this.prepare(data));
  }
}

class TypedDataSignHelper {
  constructor(contentsTypes, contentsTypeName = Object.keys(contentsTypes).at(0)) {
    this.contentsTypes = contentsTypes;
    this.contentsTypeName = contentsTypeName;
  }

  static from(contentsTypes, contentsTypeName = Object.keys(contentsTypes).at(0)) {
    return new TypedDataSignHelper(contentsTypes, contentsTypeName);
  }

  hashStruct(name, message) {
    return message.contents
      ? ethers.TypedDataEncoder.hashStruct(name, this.allTypes(message), message)
      : ethers.TypedDataEncoder.hashStruct(name, this.contentsTypes, message);
  }

  hash(domain, message) {
    return message.contents
      ? ethers.TypedDataEncoder.hash(domain, this.allTypes(message), message)
      : ethers.TypedDataEncoder.hash(domain, this.contentsTypes, message);
  }

  sign(signTypedData, domain, message) {
    const types = this.allTypes(message);
    return Promise.resolve(signTypedData(domain, types, message)).then(signature =>
      ethers.concat([
        signature,
        ethers.TypedDataEncoder.hashDomain(domain), // appDomainSeparator
        ethers.TypedDataEncoder.hashStruct(this.contentsTypeName, types, message.contents), // contentsHash
        ethers.toUtf8Bytes(this.contentDescr),
        ethers.toBeHex(this.contentDescr.length, 2),
      ]),
    );
  }

  static hashStruct(name, types, message) {
    return TypedDataSignHelper.from(types).hashStruct(name, message);
  }

  static hash(domain, types, message) {
    return TypedDataSignHelper.from(types).hash(domain, message);
  }

  static sign(signer, domain, types, message) {
    return TypedDataSignHelper.from(types).sign(signer, domain, message);
  }

  get contentDescr() {
    // Examples values
    //
    // contentsTypeName         B
    // typedDataSignType        TypedDataSign(B contents,...)A(uint256 v)B(Z z)Z(A a)
    // contentsType             A(uint256 v)B(Z z)Z(A a)
    // contentsDescr            A(uint256 v)B(Z z)Z(A a)B
    const types = this.allTypes({});
    const typedDataSignType = ethers.TypedDataEncoder.from(types).encodeType('TypedDataSign');
    const contentsType = typedDataSignType.slice(typedDataSignType.indexOf(')') + 1); // Remove TypedDataSign (first object)
    return contentsType + (contentsType.startsWith(this.contentsTypeName) ? '' : this.contentsTypeName);
  }

  // internal
  allTypes(message) {
    return {
      TypedDataSign: [...formatType({ contents: this.contentsTypeName }), ...domainType(message)],
      ...this.contentsTypes,
    };
  }
}

module.exports = {
  PersonalSignHelper,
  TypedDataSignHelper,
};
