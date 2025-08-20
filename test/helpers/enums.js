const enums = require('@openzeppelin/contracts/test/helpers/enums');

module.exports = {
  ...enums,
  EmailProofError: enums.Enum(
    'NoError',
    'DKIMPublicKeyHash',
    'MaskedCommandLength',
    'MismatchedCommand',
    'InvalidFieldPoint',
    'EmailProof',
  ),
  Case: enums.EnumTyped('CHECKSUM', 'LOWERCASE', 'UPPERCASE', 'ANY'),
  OperationState: enums.Enum('Unknown', 'Scheduled', 'Ready', 'Expired', 'Executed', 'Canceled'),
};
