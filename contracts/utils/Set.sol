// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/// @dev non-iterable variant of OpenZeppelin's EnumerableSet library.
library Set {
    struct Bytes32Set {
        mapping(bytes32 value => bool) _data;
    }

    function insert(Bytes32Set storage self, bytes32 value) internal returns (bool) {
        if (!self._data[value]) {
            self._data[value] = true;
            return true;
        } else {
            return false;
        }
    }

    function remove(Bytes32Set storage self, bytes32 value) internal returns (bool) {
        if (self._data[value]) {
            self._data[value] = false;
            return true;
        } else {
            return false;
        }
    }

    function contains(Bytes32Set storage self, bytes32 value) internal view returns (bool) {
        return self._data[value];
    }
}
