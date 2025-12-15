// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC7786Recipient} from "@openzeppelin/contracts/interfaces/draft-IERC7786.sol";

contract ERC7786RecipientRevertMock is IERC7786Recipient {
    function receiveMessage(bytes32, bytes calldata, bytes calldata) public payable virtual returns (bytes4) {
        revert();
    }
}
