// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {CAIP2} from "./CAIP-2.sol";
import {Bytes} from "./Bytes.sol";

// account_id:        chain_id + ":" + account_address
// chain_id:          [-a-z0-9]{3,8}:[-_a-zA-Z0-9]{1,32} (See [CAIP-2][])
// account_address:   [-.%a-zA-Z0-9]{1,128}
library CAIP10 {
    using SafeCast for uint256;
    using Bytes for bytes;

    bytes1 private constant COLON = ":";

    function toString(string memory caip2, string memory accountId) internal pure returns (string memory) {
        return string(abi.encodePacked(caip2, COLON, accountId));
    }

    function parse(string memory caip10) internal pure returns (string memory caip2, string memory accountId) {
        bytes memory accountBuffer = bytes(caip10);
        uint8 firstSeparatorIndex = accountBuffer.find(COLON, 0).toUint8();
        uint256 lastSeparatorIndex = accountBuffer.find(COLON, firstSeparatorIndex).toUint8();
        return (_extractCAIP2(accountBuffer, lastSeparatorIndex), _extractAccountId(accountBuffer, lastSeparatorIndex));
    }

    function currentId(string memory accountId) internal view returns (string memory) {
        (bytes8 namespace, bytes32 ref) = CAIP2.currentId();
        return toString(CAIP2.toString(namespace, ref), accountId);
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
}
