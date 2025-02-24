const { Enum } = require('@openzeppelin/contracts/test/helpers/enums');
const { formatType } = require('@openzeppelin/contracts/test/helpers/eip712');

class SocialRecoveryExecutorHelper {
  static RecoveryStatus = Enum('NotStarted', 'Started', 'Ready');
  static START_RECOVERY_TYPEHASH = {
    StartRecovery: formatType({ account: 'address', executionCalldata: 'bytes', nonce: 'uint256' }),
  };
  static CANCEL_RECOVERY_TYPEHASH = {
    CancelRecovery: formatType({ account: 'address', nonce: 'uint256' }),
  };
  static sortGuardianSignatures(guardianSignatures) {
    return guardianSignatures.sort((a, b) => {
      if (a.signer < b.signer) return -1;
      if (a.signer > b.signer) return 1;
      return 0;
    });
  }
}

module.exports = {
  SocialRecoveryExecutorHelper,
};
