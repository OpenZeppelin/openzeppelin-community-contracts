const { Enum } = require('@openzeppelin/contracts/test/helpers/enums');
const { formatType } = require('@openzeppelin/contracts/test/helpers/eip712');

const SocialRecoveryExecutorHelper = {
  RecoveryStatus: Enum('NotStarted', 'Started', 'Ready'),
  START_RECOVERY_TYPEHASH: {
    StartRecovery: formatType({ account: 'address', executionCalldata: 'bytes', nonce: 'uint256' }),
  },
  CANCEL_RECOVERY_TYPEHASH: {
    CancelRecovery: formatType({ account: 'address', nonce: 'uint256' }),
  },
};

module.exports = {
  SocialRecoveryExecutorHelper,
};
