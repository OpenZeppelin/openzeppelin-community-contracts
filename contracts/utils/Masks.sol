// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/// @dev Library for handling bit masks
library Masks {
    using Masks for *;

    type Mask is bytes32;

    /// @dev Returns a new mask with the bit at `group` index set to 1.
    function toMask(uint8 group) internal pure returns (Mask) {
        return Mask.wrap(bytes32(1 << group));
    }

    /// @dev Returns a new mask with the bits at `groups` indices set to 1.
    function toMask(uint8[] memory groups) internal pure returns (Mask) {
        Masks.Mask set = Mask.wrap(0);
        for (uint256 i = 0; i < groups.length; ++i) {
            set = set.union(groups[i].toMask());
        }
        return set;
    }

    /// @dev Get value of the mask at `group` index
    function get(Mask self, uint8 group) internal pure returns (bool) {
        return !group.toMask().intersection(self).isEmpty();
    }

    /// @dev Whether the mask is `bytes32(0)`
    function isEmpty(Mask self) internal pure returns (bool) {
        return Mask.unwrap(self) == bytes32(0);
    }

    /// @dev Invert the bits of a mask
    function complement(Mask m1) internal pure returns (Mask) {
        return Mask.wrap(~Mask.unwrap(m1));
    }

    /// @dev Perform a bitwise OR operation on two masks
    function union(Mask m1, Mask m2) internal pure returns (Mask) {
        return Mask.wrap(Mask.unwrap(m1) | Mask.unwrap(m2));
    }

    /// @dev Perform a bitwise AND operation on two masks
    function intersection(Mask m1, Mask m2) internal pure returns (Mask) {
        return Mask.wrap(Mask.unwrap(m1) & Mask.unwrap(m2));
    }

    /// @dev Perform a bitwise difference operation on two masks (m1 - m2)
    function difference(Mask m1, Mask m2) internal pure returns (Mask) {
        return m1.intersection(m2.complement());
    }

    /// @dev Returns the symmetric difference (∆) of two masks, also known as disjunctive union or exclusive OR (XOR)
    function symmetricDifference(Mask m1, Mask m2) internal pure returns (Mask) {
        return m1.union(m2).difference(m1.intersection(m2));
    }
}
