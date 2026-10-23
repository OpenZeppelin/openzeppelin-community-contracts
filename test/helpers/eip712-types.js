import { formatType } from '@openzeppelin/contracts/test/helpers/eip712-types';

export const MultisigConfirmation = formatType({
  account: 'address',
  module: 'address',
  deadline: 'uint256',
});
