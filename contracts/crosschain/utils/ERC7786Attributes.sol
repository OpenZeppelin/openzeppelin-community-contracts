// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC7786Attributes} from "../../interfaces/IERC7786Attributes.sol";

library ERC7786Attributes {
    function tryDecodeRequestRelay(
        bytes memory attribute
    ) internal pure returns (bool success, uint256 value, uint256 gasLimit, address refundRecipient) {
        success = bytes4(attribute) == IERC7786Attributes.requestRelay.selector && attribute.length >= 0x64;

        assembly ("memory-safe") {
            value := mul(success, mload(add(attribute, 0x24)))
            gasLimit := mul(success, mload(add(attribute, 0x44)))
            refundRecipient := mul(success, mload(add(attribute, 0x64)))
        }
    }

    function tryDecodeRequestRelayCalldata(
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
