// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC7786Attributes} from "../../interfaces/IERC7786Attributes.sol";

/// @dev Library of helper to parse/process ERC-7786 attributes
library ERC7786Attributes {
    /// @dev Parse the `requestRelay(uint256,uint256,address)` (0x4cbb573a) attribute into its components.
    function tryDecodeRequestRelay(
        bytes calldata attribute
    ) internal pure returns (bool success, uint256 value, uint256 gasLimit, address refundRecipient) {
        success = bytes4(attribute) == IERC7786Attributes.requestRelay.selector && attribute.length >= 0x64;

        assembly ("memory-safe") {
            value := mul(success, calldataload(add(attribute.offset, 0x04)))
            gasLimit := mul(success, calldataload(add(attribute.offset, 0x24)))
            refundRecipient := mul(success, calldataload(add(attribute.offset, 0x44)))
        }
    }
}
