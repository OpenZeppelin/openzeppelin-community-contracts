const { formatType } = require('@openzeppelin/contracts/test/helpers/eip712-types');
const { mapValues } = require('@openzeppelin/contracts/test/helpers/iterate');

module.exports = mapValues(
  {
    PackedUserOperation: {
      sender: 'address',
      nonce: 'uint256',
      initCode: 'bytes',
      callData: 'bytes',
      accountGasLimits: 'bytes32',
      preVerificationGas: 'uint256',
      gasFees: 'bytes32',
      paymasterAndData: 'bytes',
    },
    UserOperationRequest: {
      sender: 'address',
      nonce: 'uint256',
      initCode: 'bytes',
      callData: 'bytes',
      accountGasLimits: 'bytes32',
      preVerificationGas: 'uint256',
      gasFees: 'bytes32',
      paymasterVerificationGasLimit: 'uint256',
      paymasterPostOpGasLimit: 'uint256',
      validAfter: 'uint48',
      validUntil: 'uint48',
    },
    MultisigConfirmation: {
      account: 'address',
      module: 'address',
      deadline: 'uint256',
    },
  },
  formatType,
);
