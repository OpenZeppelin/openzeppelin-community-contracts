// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Bytes {
    /// @dev Forward search for `s` in `buffer`
    /// * If `s` is present in the buffer, returns the index of the first instance
    /// * If `s` is not present in the buffer, returns the length of the buffer
    function find(bytes memory buffer, bytes1 s) internal pure returns (uint256) {
        return find(buffer, s, 0);
    }

    /// @dev Forward search for `s` in `buffer` starting at position `pos`
    /// * If `s` is present in the buffer (at or after `pos`), returns the index of the next instance
    /// * If `s` is not present in the buffer (at or after `pos`), returns the length of the buffer
    function find(bytes memory buffer, bytes1 s, uint256 pos) internal pure returns (uint256) {
        unchecked {
            uint256 length = buffer.length;
            for (uint256 i = pos; i < length; ++i) {
                if (buffer[i] == s) {
                    return i;
                }
            }
            return length;
        }
    }

    /// @dev Backward search for `s` in `buffer`
    /// * If `s` is present in the buffer, returns the index of the last instance
    /// * If `s` is not present in the buffer, returns the length of the buffer
    function findLastOf(bytes memory buffer, bytes1 s) internal pure returns (uint256) {
        return findLastOf(buffer, s, buffer.length);
    }

    /// @dev Backward search for `s` in `buffer` starting at position `pos`
    /// * If `s` is present in the buffer (before `pos`), returns the index of the previous instance
    /// * If `s` is not present in the buffer (before `pos`), returns the length of the buffer
    function findLastOf(bytes memory buffer, bytes1 s, uint256 pos) internal pure returns (uint256) {
        unchecked {
            for (uint256 i = pos; i > 0; --i) {
                if (buffer[i - 1] == s) {
                    return i - 1;
                }
            }
            return buffer.length;
        }
    }

    function slice(bytes memory buffer, uint256 start) internal pure returns (bytes memory) {
        return slice(buffer, start, buffer.length);
    }

    function slice(bytes memory buffer, uint256 start, uint256 end) internal pure returns (bytes memory) {
        bytes memory result = new bytes(end - start);
        for (uint256 i = start; i < end; ++i) {
            result[i - start] = buffer[i];
        }
        return result;
    }
}
