// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20Upgradeable, ERC20CollateralUpgradeable} from "../../token/ERC20/extensions/ERC20CollateralUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract ERC20CollateralMockUpgradeable is Initializable, ERC20CollateralUpgradeable {
    uint48 private _timestamp;
    function __ERC20CollateralMock_init(
        uint48 liveness_,
        string memory name_,
        string memory symbol_
    ) internal onlyInitializing {
        __ERC20_init_unchained(name_, symbol_);
        __ERC20Collateral_init_unchained(liveness_);
        __ERC20CollateralMock_init_unchained(liveness_, name_, symbol_);
    }

    function __ERC20CollateralMock_init_unchained(
        uint48,
        string memory,
        string memory
    ) internal onlyInitializing {
        _timestamp = clock();
    }

    function collateral() public view override returns (uint256 amount, uint48 timestamp) {
        return (type(uint128).max, _timestamp);
    }
}
