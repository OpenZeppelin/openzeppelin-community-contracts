// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/Pausable.sol)

pragma solidity ^0.8.20;

import {Pausable} from "./Pausable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title DefaultPausable
 * @author @CarlosAlegreUr
 *
 * @dev A default implementation of {Pausable} that uses a `block.timestamp` based `clock()`.
 */
abstract contract DefaultPausable is Pausable {
    /**
     * @dev Clock is used here for time checkings on pauses with defined end-date.
     *
     * @dev IERC6372 implementation of a clock() based on native `block.timestamp`.
     */
    function clock() public view virtual override returns (uint48) {
        return SafeCast.toUint48(block.timestamp);
    }

    /**
     * @dev IERC6372 implementation of a CLOCK_MODE() based on timestamp.
     *
     * Override this function to implement a different clock mode, if so must be done following {IERC6372} specification.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        return "mode=timestamp";
    }
}
