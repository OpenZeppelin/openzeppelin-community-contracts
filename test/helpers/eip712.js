const { types, formatType } = require('../../lib/@openzeppelin-contracts/test/helpers/eip712');
const { mapValues } = require('../../lib/@openzeppelin-contracts/test/helpers/iterate');

module.exports = {
  ...types,
  ...mapValues(
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
        entrypoint: 'address',
      },
    },
    formatType,
  ),
};
