// SPDX-License-Identifier: MIT

pragma solidity ^0.8.8;

import {IERC7786Recipient} from "@openzeppelin/contracts/interfaces/IERC7786.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract ERC7786RecipientRevertMockUpgradeable is Initializable, IERC7786Recipient {
    function __ERC7786RecipientRevertMock_init() internal onlyInitializing {
    }

    function __ERC7786RecipientRevertMock_init_unchained() internal onlyInitializing {
    }
    function receiveMessage(bytes32, bytes calldata, bytes calldata) public payable virtual returns (bytes4) {
        revert();
    }
}
