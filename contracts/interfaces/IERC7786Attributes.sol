// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

/**
 * @dev Standard attributes for ERC-7786. These attributes may be standardized in different ERCs.
 */
interface IERC7786Attributes {
    function requestRelay(uint256 value, uint256 gasLimit, address refundRecipient) external;
}
