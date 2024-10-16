// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC1363Receiver} from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";

/**
 * @dev This contract exposes the 667 `onTokenTransfer` hook on top of {IERC1363Receiver-onTransferReceived}.
 *
 * Inheriting from this adapter makes your `ERC1363Receiver` contract automatically compatible with tokens, such as
 * Chainlink's Link, that implement the 667 interface for transferAndCall.
 */
abstract contract OnTokenTransferAdapter is IERC1363Receiver {
    function onTokenTransfer(address from, uint256 amount, bytes calldata data) public virtual returns (bool) {
        // Rewrite call as IERC1363.onTransferReceived
        // This uses delegate call to keep the correct sender (token contracts)
        //
        // Note that since 667 doesn't implement `transferFromAndCall`, this hook was called by a simple
        // `transferAndCall` and thus the operator is necessarily the `from` address.
        (bool success, bytes memory returndata) = address(this).delegatecall(
            abi.encodeCall(IERC1363Receiver.onTransferReceived, (from, from, amount, data))
        );
        // check success and return as boolean
        return
            success &&
            returndata.length >= 0x20 &&
            abi.decode(returndata, (bytes4)) == IERC1363Receiver.onTransferReceived.selector;
    }
}
