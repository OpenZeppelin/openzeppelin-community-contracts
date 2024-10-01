// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {StringsUnreleased} from "./Strings.sol";
import {Bytes} from "./Bytes.sol";
import {CAIP2} from "./CAIP-2.sol";

// account_id:        chain_id + ":" + account_address
// chain_id:          [-a-z0-9]{3,8}:[-_a-zA-Z0-9]{1,32} (See [CAIP-2][])
// account_address:   [-.%a-zA-Z0-9]{1,128}
library CAIP10 {
    using SafeCast for uint256;
    using StringsUnreleased for address;
    using Bytes for bytes;

    function local(address account) internal view returns (string memory) {
        return format(CAIP2.local(), account.toChecksumHexString());
    }

    function format(string memory caip2, string memory account) internal pure returns (string memory) {
        return string.concat(caip2, ":", account);
    }

    function parse(string memory caip10) internal pure returns (string memory caip2, string memory account) {
        bytes memory buffer = bytes(caip10);

        uint256 pos = buffer.lastIndexOf(":");
        return (string(buffer.slice(0, pos)), string(buffer.slice(pos + 1)));
    }
}
