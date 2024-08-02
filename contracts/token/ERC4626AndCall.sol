// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts@master/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts@master/token/ERC20/extensions/ERC4626.sol";
import {IERC1363, ERC1363} from "@openzeppelin/contracts@master/token/ERC20/extensions/ERC1363.sol";
import {ERC1363Utils} from "@openzeppelin/contracts@master/token/ERC20/utils/ERC1363Utils.sol";
import {SafeERC20} from "@openzeppelin/contracts@master/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev Variant of {ERC4626} that provide improved composability using ERC-1363.
 *
 * This contains 4 new functions:
 *
 * * {depositAndCall}: A variant of {ERC4626-deposit} that calls the ERC-1363 hook on the receiver of the shares. The
 *   receiver will be notified like if he had received the shares using an ERC-1363 `transferAndCall` of
 *   `transferFromAndCall`
 *
 * * {mintAndCall}: A variant of {ERC4626-mint} that calls the ERC-1363 hook on the receiver of the shares. The
 *   receiver will be notified like if he had received the shares using an ERC-1363 `transferAndCall` of
 *   `transferFromAndCall`
 *
 * * {withdrawAndCall}: a variant of {ERC4626-withdraw} that sends the assets to the receiver using an ERC-1363
 *   `transferAndCall`. The receiver will be notified like by the `assets` contract itself. This is only available if
 *   the asset contract to implement ERC-1363.
 *
 * * {redeemAndCall}: a variant of {ERC4626-redeem} that sends the assets to the receiver using an ERC-1363
 *   `transferAndCall`. The receiver will be notified like by the `assets` contract itself. This is only available if
 *   the asset contract to implement ERC-1363.
 */
abstract contract ERC4626AndCall is ERC4626, ERC1363 {
    /// @inheritdoc ERC4626
    function decimals() public view virtual override(ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }

    /// @dev This is simple enough: do a normal {ERC4626-deposit} then call the ERC1363 hook
    function depositAndCall(uint256 assets, address receiver, bytes memory data) public virtual returns (uint256) {
        uint256 shares = deposit(assets, receiver);
        ERC1363Utils.checkOnERC1363TransferReceived(_msgSender(), address(0), receiver, shares, data);
        return shares;
    }

    /// @dev This is simple enough: do a normal {ERC4626-mint} then call the ERC1363 hook
    function mintAndCall(uint256 shares, address receiver, bytes memory data) public virtual returns (uint256) {
        uint256 assets = mint(shares, receiver);
        ERC1363Utils.checkOnERC1363TransferReceived(_msgSender(), address(0), receiver, shares, data);
        return assets;
    }

    /// @dev Duplicate the {ERC46246-withdraw} logic, doing an {ERC1363-transferAndCall} instead of the normal {ERC20-transfer}
    function withdrawAndCall(
        uint256 assets,
        address receiver,
        address spender,
        bytes memory data
    ) public virtual returns (uint256) {
        uint256 maxAssets = maxWithdraw(spender);
        if (assets > maxAssets) revert ERC4626ExceededMaxWithdraw(spender, assets, maxAssets);
        uint256 shares = previewWithdraw(assets);
        _withdrawAndCall(_msgSender(), receiver, spender, assets, shares, data);
        return shares;
    }

    /// @dev Duplicate the {ERC46246-redeem} logic, doing an {ERC1363-transferAndCall} instead of the normal {ERC20-transfer}
    function redeemAndCall(
        uint256 shares,
        address receiver,
        address spender,
        bytes memory data
    ) public virtual returns (uint256) {
        uint256 maxShares = maxRedeem(spender);
        if (shares > maxShares) revert ERC4626ExceededMaxRedeem(spender, shares, maxShares);
        uint256 assets = previewRedeem(shares);
        _withdrawAndCall(_msgSender(), receiver, spender, assets, shares, data);
        return assets;
    }

    /// @dev Duplicate the {ERC4626-_withdraw} logic, doing an {ERC1363-transferAndCall} instead of the normal {ERC20-transfer}
    function _withdrawAndCall(
        address caller,
        address receiver,
        address spender,
        uint256 assets,
        uint256 shares,
        bytes memory data
    ) internal virtual {
        if (caller != spender) _spendAllowance(spender, caller, shares);
        _burn(spender, shares);
        SafeERC20.transferAndCallRelaxed(IERC1363(asset()), receiver, assets, data);
        emit Withdraw(caller, receiver, spender, assets, shares);
    }
}
