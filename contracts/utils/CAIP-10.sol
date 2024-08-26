// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// account_id:        chain_id + ":" + account_address
// chain_id:          [-a-z0-9]{3,8}:[-_a-zA-Z0-9]{1,32} (See [CAIP-2][])
// account_address:   [-.%a-zA-Z0-9]{1,128}
library CAIP10 {
    bytes1 constant SEMICOLON = ":";

    function toString(bytes32 chainId, string memory accountId) internal pure returns (string memory) {
        return string(abi.encodePacked(chainId, SEMICOLON, accountId));
    }

    function fromString(string memory accountStr) internal pure returns (string memory caip2, string memory accountId) {
        bytes memory accountBuffer = bytes(accountStr);
        uint256 lastSeparatorIndex = _findLastSeparatorIndex(accountBuffer);
        return (_extractCAIP2(accountBuffer, lastSeparatorIndex), _extractAccountId(accountBuffer, lastSeparatorIndex));
    }

    function _extractCAIP2(
        bytes memory accountBuffer,
        uint256 lastSeparatorIndex
    ) private pure returns (string memory chainId) {
        bytes memory _chainId = new bytes(lastSeparatorIndex);
        for (uint256 i = 0; i < lastSeparatorIndex; i++) {
            _chainId[i] = accountBuffer[i];
        }
        return string(_chainId);
    }

    function _extractAccountId(
        bytes memory accountBuffer,
        uint256 lastSeparatorIndex
    ) private pure returns (string memory) {
        uint256 length = accountBuffer.length;
        uint256 offset = lastSeparatorIndex - 1;
        bytes memory _accountId = new bytes(length - offset); // Will overflow if no separator is found
        for (uint256 i = lastSeparatorIndex + 1; i < length; i++) {
            _accountId[i - offset] = accountBuffer[i];
        }
        return string(_accountId);
    }

    function _findLastSeparatorIndex(bytes memory accountBuffer) private pure returns (uint256) {
        for (uint256 i = accountBuffer.length - 1; i >= 0; i--) {
            if (accountBuffer[i] == SEMICOLON) {
                return i;
            }
        }
        return 0;
    }
}
