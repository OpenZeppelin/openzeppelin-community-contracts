// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {PausableUntil} from "../utils/PausableUntil.sol";

abstract contract PausableUntilMock is PausableUntil {
    function clock() public view virtual override returns (uint48) {
        return SafeCast.toUint48(block.timestamp);
    }

    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        return "mode=timestamp";
    }

    function canCallWhenNotPaused() external whenNotPaused {}
    function canCallWhenPaused() external whenPaused {}
}
