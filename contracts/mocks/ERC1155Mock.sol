// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract ERC1155Mock is ERC1155 {
    constructor(string memory _uri) ERC1155(_uri) {}

    function $mintBatch(address to, uint256[] memory ids, uint256[] memory values, bytes memory data) external virtual {
        _mintBatch(to, ids, values, data);
    }
}
