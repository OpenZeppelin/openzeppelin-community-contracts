// SPDX-License-Identifier: MIT
// This file was procedurally generated from scripts/generate/templates/EnumerableSetExtended.js.

pragma solidity ^0.8.20;

import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {Hashes} from "@openzeppelin/contracts/utils/cryptography/Hashes.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of non-value
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 * - Set can be cleared (all elements removed) in O(n).
 *
 * ```solidity
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSetExtended for EnumerableSetExtended.StringSet;
 *
 *     // Declare a set state variable
 *     EnumerableSetExtended.StringSet private mySet;
 * }
 * ```
 *
 * Sets of type `string` (`StringSet`), `bytes` (`BytesSet`) and
 * `bytes32[2]` (`Bytes32x2Set`) are supported.
 *
 * [WARNING]
 * ====
 * Trying to delete such a structure from storage will likely result in data corruption, rendering the structure
 * unusable.
 * See https://github.com/ethereum/solidity/pull/11843[ethereum/solidity#11843] for more info.
 *
 * In order to clean an EnumerableSet, you can either remove all elements one by one or create a fresh instance using an
 * array of EnumerableSet.
 * ====
 *
 * NOTE: This is an extension of openzeppelin/contracts/utils/struct/EnumerableSet.sol.
 */
library EnumerableSetExtended {
    struct Bytes32x2Set {
        // Storage of set values
        bytes32[2][] _values;
        // Position is the index of the value in the `values` array plus 1.
        // Position 0 is used to mean a value is not in the set.
        mapping(bytes32 valueHash => uint256) _positions;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32x2Set storage self, bytes32[2] memory value) internal returns (bool) {
        if (!contains(self, value)) {
            self._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            self._positions[_hash(value)] = self._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32x2Set storage self, bytes32[2] memory value) internal returns (bool) {
        // We cache the value's position to prevent multiple reads from the same storage slot
        bytes32 valueHash = _hash(value);
        uint256 position = self._positions[valueHash];

        if (position != 0) {
            // Equivalent to contains(self, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 valueIndex = position - 1;
            uint256 lastIndex = self._values.length - 1;

            if (valueIndex != lastIndex) {
                bytes32[2] memory lastValue = self._values[lastIndex];

                // Move the lastValue to the index where the value to delete is
                self._values[valueIndex] = lastValue;
                // Update the tracked position of the lastValue (that was just moved)
                self._positions[_hash(lastValue)] = position;
            }

            // Delete the slot where the moved value was stored
            self._values.pop();

            // Delete the tracked position for the deleted slot
            delete self._positions[valueHash];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes all the values from a set. O(n).
     *
     * WARNING: Developers should keep in mind that this function has an unbounded cost and using it may render the
     * function uncallable if the set grows to the point where clearing it consumes too much gas to fit in a block.
     */
    function clear(Bytes32x2Set storage self) internal {
        bytes32[2][] storage v = self._values;

        uint256 len = length(self);
        for (uint256 i = 0; i < len; ++i) {
            delete self._positions[_hash(v[i])];
        }
        assembly ("memory-safe") {
            sstore(v.slot, 0)
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32x2Set storage self, bytes32[2] memory value) internal view returns (bool) {
        return self._positions[_hash(value)] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(Bytes32x2Set storage self) internal view returns (uint256) {
        return self._values.length;
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(Bytes32x2Set storage self, uint256 index) internal view returns (bytes32[2] memory) {
        return self._values[index];
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(Bytes32x2Set storage self) internal view returns (bytes32[2][] memory) {
        return self._values;
    }

    /**
     * @dev Return a slice of the set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(Bytes32x2Set storage set, uint256 start, uint256 end) internal view returns (bytes32[2][] memory) {
        unchecked {
            end = Math.min(end, length(set));
            start = Math.min(start, end);

            uint256 len = end - start;
            bytes32[2][] memory result = new bytes32[2][](len);
            for (uint256 i = 0; i < len; ++i) {
                result[i] = set._values[start + i];
            }
            return result;
        }
    }

    function _hash(bytes32[2] memory value) private pure returns (bytes32) {
        return Hashes.efficientKeccak256(value[0], value[1]);
    }
}
