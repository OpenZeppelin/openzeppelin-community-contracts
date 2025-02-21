const SocialRecoveryExecutorHelper = {
  RecoveryStatus: {
    NotStarted: 0,
    Started: 1,
    Cancelled: 2,
  },
  RECOVERY_MESSAGE_TYPE: {
    RecoveryMessage: [
      { name: 'account', type: 'address' },
      { name: 'nonce', type: 'uint256' },
    ],
  },
};
module.exports = {
  SocialRecoveryExecutorHelper,
};
