// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {CAIP2} from "./CAIP-2.sol";

library CAIP10 {
    using CAIP2 for CAIP2.ChainId;

    // account_id:        chain_id + ":" + account_address
    // chain_id:          [-a-z0-9]{3,8}:[-_a-zA-Z0-9]{1,32} (See [CAIP-2][])
    // account_address:   [-.%a-zA-Z0-9]{1,128}
    struct Account {
        CAIP2.ChainId _chainId;
        string _accountId; // Often referred to as address
    }

    function toString(Account memory account) internal pure returns (string memory) {
        return string(abi.encodePacked(account._chainId.toString(), CAIP2.SEMICOLON, account._accountId));
    }

    function fromString(string memory accountStr) internal pure returns (Account memory account) {
        bytes memory accountBuffer = bytes(accountStr);
        uint256 lastSeparatorIndex = _findLastSeparatorIndex(accountBuffer);
        account._chainId = extractChainId(accountBuffer, lastSeparatorIndex);
        account._accountId = extractAccountId(accountBuffer, lastSeparatorIndex);
        return account;
    }

    function extractChainId(
        bytes memory accountBuffer,
        uint256 lastSeparatorIndex
    ) internal pure returns (CAIP2.ChainId memory chainId) {
        bytes memory _chainId = new bytes(lastSeparatorIndex);
        for (uint256 i = 0; i < lastSeparatorIndex; i++) {
            _chainId[i] = accountBuffer[i];
        }
        return CAIP2.fromString(string(_chainId));
    }

    function extractAccountId(
        bytes memory accountBuffer,
        uint256 lastSeparatorIndex
    ) internal pure returns (string memory) {
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
            if (accountBuffer[i] == CAIP2.SEMICOLON) {
                return i;
            }
        }
        return 0;
    }
}
