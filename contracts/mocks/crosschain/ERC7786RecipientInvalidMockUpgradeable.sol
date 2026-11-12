// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC7786Recipient} from "@openzeppelin/contracts/interfaces/draft-IERC7786.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract ERC7786RecipientInvalidMockUpgradeable is Initializable, IERC7786Recipient {
    function __ERC7786RecipientInvalidMock_init() internal onlyInitializing {
    }

    function __ERC7786RecipientInvalidMock_init_unchained() internal onlyInitializing {
    }
    function receiveMessage(bytes32, bytes calldata, bytes calldata) public payable virtual returns (bytes4) {
        return 0xffffffff;
    }
}
