// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Bytes} from "./Bytes.sol";

// chain_id:    namespace + ":" + reference
// namespace:   [-a-z0-9]{3,8}
// reference:   [-_a-zA-Z0-9]{1,32}
library CAIP2 {
    using SafeCast for uint256;
    using Strings for uint256;
    using Bytes for bytes;

    function local() internal view returns (string memory) {
        return format("eip155", block.chainid.toString());
    }

    function format(string memory namespace, string memory ref) internal pure returns (string memory) {
        return string.concat(namespace, ":", ref);
    }

    function parse(string memory caip2) internal pure returns (string memory namespace, string memory ref) {
        bytes memory buffer = bytes(caip2);

        uint256 pos = buffer.indexOf(":");
        return (string(buffer.slice(0, pos)), string(buffer.slice(pos + 1)));
    }
}
