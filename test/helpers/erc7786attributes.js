const { Interface } = require('ethers');

module.exports = Interface.from(['function requestRelay(uint256 value, uint256 gasLimit, address refundRecipient)']);
