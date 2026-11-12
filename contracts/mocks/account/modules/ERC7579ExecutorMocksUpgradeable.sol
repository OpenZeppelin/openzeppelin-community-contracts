// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7579ExecutorUpgradeable} from "../../../account/modules/ERC7579ExecutorUpgradeable.sol";
import {ERC7579DelayedExecutorUpgradeable} from "../../../account/modules/ERC7579DelayedExecutorUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract ERC7579ExecutorMockUpgradeable is Initializable, ERC7579ExecutorUpgradeable {
    function __ERC7579ExecutorMock_init() internal onlyInitializing {
    }

    function __ERC7579ExecutorMock_init_unchained() internal onlyInitializing {
    }
    function onInstall(bytes calldata data) external {}

    function onUninstall(bytes calldata data) external {}

    function _validateExecution(
        address,
        bytes32,
        bytes32,
        bytes calldata data
    ) internal pure override returns (bytes calldata) {
        return data;
    }
}

abstract contract ERC7579DelayedExecutorMockUpgradeable is Initializable, ERC7579DelayedExecutorUpgradeable {
    function __ERC7579DelayedExecutorMock_init() internal onlyInitializing {
    }

    function __ERC7579DelayedExecutorMock_init_unchained() internal onlyInitializing {
    }
    function _validateSchedule(address account, bytes32, bytes32, bytes calldata) internal view override {
        require(msg.sender == account);
    }

    function _validateCancel(address account, bytes32, bytes32, bytes calldata) internal view override {
        require(msg.sender == account);
    }
}
