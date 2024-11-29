// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20, ERC20Collateral} from "../../token/ERC20/extensions/ERC20Collateral.sol";

abstract contract ERC20CollateralMock is ERC20Collateral {
    uint48 private _timestamp;
    constructor(
        uint48 liveness_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC20Collateral(liveness_) {
        _timestamp = clock();
    }

    function collateral() public view override returns (uint256 amount, uint48 timestamp) {
        return (type(uint128).max, _timestamp);
    }
}
