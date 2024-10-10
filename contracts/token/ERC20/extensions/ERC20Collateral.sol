// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Extension of {ERC20} that limits the supply of tokens based
 * on a collateral amount and time-based expiration.
 *
 * The {collateral} function must be implemented to return the collateral
 * data. This function can call external oracles or use any local storage.
 */
abstract contract ERC20Collateral is ERC20 {
    // Structure that stores the details of the collateral
    struct Collateral {
        uint256 amount;
        uint256 timestamp;
    }

    /**
     * @dev Liveness duration of collateral, defined in seconds.
     */
    uint256 private immutable _liveness;

    /**
     * @dev Total supply cap has been exceeded.
     */
    error ERC20ExceededSupply(uint256 increasedSupply, uint256 cap);

    /**
     * @dev Collateral amount has expired.
     */
    error ERC20ExpiredCollateral(uint256 timestamp, uint256 expiration);

    /**
     * @dev Sets the value of the `_liveness`. This value is immutable, it can only be
     * set once during construction.
     */
    constructor(uint256 liveness_) {
        _liveness = liveness_;
    }

    /**
     * @dev Returns the minimum liveness duration of collateral.
     */
    function liveness() public view virtual returns (uint256) {
        return _liveness;
    }

    /**
     * @dev Returns the collateral data of the token.
     */
    function collateral() public view virtual returns (Collateral memory);

    /**
     * @dev See {ERC20-_update}.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);

        if (from == address(0)) {
            Collateral memory _collateral = collateral();

            uint256 expiration = _collateral.timestamp + liveness();
            if (expiration < block.timestamp) {
                revert ERC20ExpiredCollateral(_collateral.timestamp, expiration);
            }

            uint256 supply = totalSupply();
            if (supply > _collateral.amount) {
                revert ERC20ExceededSupply(supply, _collateral.amount);
            }
        }
    }
}
