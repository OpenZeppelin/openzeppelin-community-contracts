const enums = require('@openzeppelin/contracts/test/helpers/enums');

module.exports = {
  ...enums,
  EmailProofError: enums.Enum(
    'NoError',
    'DKIMPublicKeyHash',
    'MaskedCommandLength',
    'SkippedCommandPrefixSize',
    'MismatchedCommand',
    'EmailProof',
  ),
  JWTProofError: enums.Enum('NoError', 'JWTPublicKeyHash', 'MaskedCommandLength', 'MismatchedCommand', 'JWTProof'),
  Case: enums.EnumTyped('CHECKSUM', 'LOWERCASE', 'UPPERCASE', 'ANY'),
  OperationState: enums.Enum('Unknown', 'Scheduled', 'Ready', 'Expired', 'Executed', 'Canceled'),
};
