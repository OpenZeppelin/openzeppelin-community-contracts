// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC7579ModuleMockUpgradeable} from "./ERC7579ModuleMockUpgradeable.sol";
import {MODULE_TYPE_HOOK, IERC7579Hook} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract ERC7579HookMockUpgradeable is Initializable, ERC7579ModuleMockUpgradeable, IERC7579Hook {
    event PreCheck(address sender, uint256 value, bytes data);
    event PostCheck(bytes hookData);

    function __ERC7579HookMock_init() internal onlyInitializing {
        __ERC7579ModuleMock_init_unchained(MODULE_TYPE_HOOK);
    }

    function __ERC7579HookMock_init_unchained() internal onlyInitializing {
    }
    function preCheck(
        address msgSender,
        uint256 value,
        bytes calldata msgData
    ) external returns (bytes memory hookData) {
        emit PreCheck(msgSender, value, msgData);
        return msgData;
    }

    function postCheck(bytes calldata hookData) external {
        emit PostCheck(hookData);
    }
}
