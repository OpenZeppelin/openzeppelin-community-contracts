// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Masks} from "@openzeppelin/community-contracts/utils/Masks.sol";

contract MasksTest is Test {
    using Masks for Masks.Mask;

    function testToMask(uint8 group) public pure {
        assertEq(Masks.toMask(group).get(group), true);
    }

    function testToMaskArray(uint8[] memory groups) public pure {
        Masks.Mask mask = Masks.toMask(groups);
        for (uint256 i = 0; i < groups.length; ++i) {
            assertEq(mask.get(groups[i]), true);
        }
    }

    function testIsEmpty(bytes32 mask) public pure {
        assertEq(Masks.Mask.wrap(mask).isEmpty(), mask == 0);
    }

    function testComplement(bytes32 mask) public pure {
        Masks.Mask m = Masks.Mask.wrap(mask).complement();
        assertEq(Masks.Mask.unwrap(m), ~mask);
    }

    function testUnion(bytes32 m1, bytes32 m2) public pure {
        Masks.Mask m = Masks.Mask.wrap(m1).union(Masks.Mask.wrap(m2));
        assertEq(Masks.Mask.unwrap(m), m1 | m2);
    }

    function testIntersection(bytes32 m1, bytes32 m2) public pure {
        Masks.Mask m = Masks.Mask.wrap(m1).intersection(Masks.Mask.wrap(m2));
        assertEq(Masks.Mask.unwrap(m), m1 & m2);
    }

    function testDifference(bytes32 m1, bytes32 m2) public pure {
        Masks.Mask m = Masks.Mask.wrap(m1).difference(Masks.Mask.wrap(m2));
        assertEq(Masks.Mask.unwrap(m), m1 & ~m2);
    }

    function testSymetricDifference(bytes32 m1, bytes32 m2) public pure {
        Masks.Mask m = Masks.Mask.wrap(m1).symmetricDifference(Masks.Mask.wrap(m2));
        assertEq(Masks.Mask.unwrap(m), m1 ^ m2);
    }
}
