// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";

abstract contract OnTokenTransferAdapter is IERC1363Receiver {
    function onTokenTransfer(address from, uint256 amount, bytes calldata data) public virtual returns (bool) {
        // Rewrite call as IERC1363.onTransferReceived
        // This uses delegate call to keep the correct sender (token contracts)
        //
        // TODO: use operator = 0 or operator = from ?
        (bool success, bytes memory returndata) = address(this).delegatecall(
            abi.encodeCall(IERC1363Receiver.onTransferReceived, (address(0), from, amount, data))
        );
        // check success and return as boolean
        return
            success &&
            returndata.length >= 0x20 &&
            abi.decode(returndata, (bytes4)) == IERC1363Receiver.onTransferReceived.selector;
    }
}
