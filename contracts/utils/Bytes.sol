// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Bytes {
    function find(bytes memory input, bytes1 chr, uint256 cursor) internal pure returns (uint256) {
        uint256 length = input.length;
        for (uint256 i = cursor; i < length; ++i) {
            if (input[i] == chr) {
                return i;
            }
        }
        return length;
    }
}
