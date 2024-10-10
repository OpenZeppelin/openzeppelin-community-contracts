// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20, ERC20Collateral} from "../../token/ERC20/extensions/ERC20Collateral.sol";

abstract contract ERC20CollateralMock is ERC20Collateral {
    constructor(
        uint256 minLiveness_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) ERC20Collateral(minLiveness_) {}

    function collateral() public view override returns (ERC20Collateral.Collateral memory) {
        return ERC20Collateral.Collateral({amount: type(uint128).max, timestamp: block.timestamp + 1 days});
    }
}
