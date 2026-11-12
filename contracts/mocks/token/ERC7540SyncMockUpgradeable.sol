// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7540Upgradeable} from "../../token/ERC20/extensions/ERC7540Upgradeable.sol";
import {ERC7540SyncDepositUpgradeable} from "../../token/ERC20/extensions/ERC7540SyncDepositUpgradeable.sol";
import {ERC7540SyncRedeemUpgradeable} from "../../token/ERC20/extensions/ERC7540SyncRedeemUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract ERC7540SyncMockUpgradeable is Initializable, ERC7540SyncDepositUpgradeable, ERC7540SyncRedeemUpgradeable {    function __ERC7540SyncMock_init() internal onlyInitializing {
    }

    function __ERC7540SyncMock_init_unchained() internal onlyInitializing {
    }
}
