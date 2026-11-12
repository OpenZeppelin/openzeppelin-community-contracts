// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @dev Extension of {ERC20} that limits the supply of tokens based
 * on a collateral amount and time-based expiration.
 *
 * The {collateral} function must be implemented to return the collateral
 * data. This function can call external oracles or use any local storage.
 */
abstract contract ERC20CollateralUpgradeable is Initializable, ERC20Upgradeable, IERC6372 {
    /// @custom:storage-location erc7201:openzeppelin.storage.ERC20Collateral
    struct ERC20CollateralStorage {
        /**
         * @dev Liveness duration of collateral, defined in seconds.
         */
        uint48 _liveness;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20Collateral")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20CollateralStorageLocation = 0x911031b944328ca76978c8bbca4924eb820246b3c75d49608f7c1b732acd8d00;

    function _getERC20CollateralStorage() private pure returns (ERC20CollateralStorage storage $) {
        assembly {
            $.slot := ERC20CollateralStorageLocation
        }
    }

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
    function __ERC20Collateral_init(uint48 liveness_) internal onlyInitializing {
        __ERC20Collateral_init_unchained(liveness_);
    }

    function __ERC20Collateral_init_unchained(uint48 liveness_) internal onlyInitializing {
        ERC20CollateralStorage storage $ = _getERC20CollateralStorage();
        $._liveness = liveness_;
    }

    /**
     * @dev Returns the minimum liveness duration of collateral.
     */
    function liveness() public view virtual returns (uint48) {
        ERC20CollateralStorage storage $ = _getERC20CollateralStorage();
        return $._liveness;
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
