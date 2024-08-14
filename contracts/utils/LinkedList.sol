// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Panic} from "@openzeppelin/contracts@master/utils/Panic.sol";

/**
 * @dev A linked list implemented in an array.
 */
library LinkedList {
    struct Node {
        uint256 next;
        uint256 prev;
        bytes32 _value;
    }

    struct List {
        Node[] nodes;
    }

    function insert(Node[] storage self, uint256 index, uint256 value) internal {
        if (index > self.length) revert Panic.panic(Panic.ARRAY_OUT_OF_BOUNDS);

        self.push(self[index]);
        self[index].prev = self.length - 1;
        self[index].next = value;
    }
}
