import { Enum, EnumTyped } from '@openzeppelin/contracts/test/helpers/enums';

export * from '@openzeppelin/contracts/test/helpers/enums';

export const EmailProofError = Enum(
  'NoError',
  'DKIMPublicKeyHash',
  'MaskedCommandLength',
  'MismatchedCommand',
  'InvalidFieldPoint',
  'EmailProof',
);

export const Case = EnumTyped('CHECKSUM', 'LOWERCASE', 'UPPERCASE', 'ANY');

export const OperationState = Enum('Unknown', 'Scheduled', 'Ready', 'Expired', 'Executed', 'Canceled');
