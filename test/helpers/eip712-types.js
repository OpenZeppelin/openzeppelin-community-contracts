const { formatType } = require('@openzeppelin/contracts/test/helpers/eip712-types');
const { mapValues } = require('@openzeppelin/contracts/test/helpers/iterate');

module.exports = mapValues(
  {
    MultisigConfirmation: {
      account: 'address',
      module: 'address',
      deadline: 'uint256',
    },
  },
  formatType,
);
