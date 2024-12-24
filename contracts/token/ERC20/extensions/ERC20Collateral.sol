// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

/**
 * @dev Extension of {ERC20} that limits the supply of tokens based
 * on a collateral amount and time-based expiration.
 *
 * The {collateral} function must be implemented to return the collateral
 * data. This function can call external oracles or use any local storage.
 */
abstract contract ERC20Collateral is ERC20, IERC6372 {
    /**
     * @dev Liveness duration of collateral, defined in seconds.
     */
    uint48 private immutable _liveness;

    /**
     * @dev Total supply cap has been exceeded.
     */
    error ERC20ExceededSupply(uint256 increasedSupply, uint256 cap);

    /**
     * @dev Collateral amount has expired.
     */
    error ERC20ExpiredCollateral(uint48 timestamp, uint48 expiration);

    /**
     * @dev Sets the value of the `_liveness`. This value is immutable, it can only be
     * set once during construction.
     */
    constructor(uint48 liveness_) {
        _liveness = liveness_;
    }

    /**
     * @dev Returns the minimum liveness duration of collateral.
     */
    function liveness() public view virtual returns (uint48) {
        return _liveness;
    }

    /**
     * @inheritdoc IERC6372
     */
    function clock() public view virtual returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @inheritdoc IERC6372
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual returns (string memory) {
        return "mode=timestamp";
    }

    /**
     * @dev Returns the collateral data of the token.
     */
    function collateral() public view virtual returns (uint256 amount, uint48 timestamp);

    /**
     * @dev See {ERC20-_update}.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);

        if (from == address(0)) {
            (uint256 amount, uint48 timestamp) = collateral();

            uint48 expiration = timestamp + liveness();
            if (expiration < clock()) {
                revert ERC20ExpiredCollateral(timestamp, expiration);
            }

            uint256 supply = totalSupply();
            if (supply > amount) {
                revert ERC20ExceededSupply(supply, amount);
            }
        }
    }
}
