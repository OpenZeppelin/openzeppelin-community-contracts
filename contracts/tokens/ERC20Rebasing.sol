// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IERC20           } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { IERC1363Receiver } from "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";
import { IERC4626         } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Math             } from "@openzeppelin/contracts/utils/math/Math.sol";
import { ERC20            } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC4626          } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

abstract contract ERC20Rebasing is ERC4626, IERC1363Receiver
{
    using Math for uint256;

    // Must be implemented depending on the choice of oracle
    function _getPrice() internal view virtual returns (uint256 price, uint256 denom);

    /****************************************************************************************************************
     *                                        Copy underlying token settings                                        *
     ****************************************************************************************************************/
    function onTransferReceived(
        address, /*operator*/
        address from,
        uint256 assets, /*amount*/
        bytes memory data
    ) external virtual returns (bytes4) {
        require(msg.sender == asset());

        // decode data
        (address receiver) = data.length < 0x20 ? (from) : abi.decode(data, (address));

        // check max deposit
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        // compute shares (rebasing), mint and emit event.
        // cannot use `_deposit` here because `_deposit` handles the transfer of underlying assets.
        uint256 shares = previewDeposit(assets);
        _mint(receiver, shares);
        emit Deposit(from, receiver, assets, shares);

        return IERC1363Receiver.onTransferReceived.selector;
    }

    /****************************************************************************************************************
     *                                        ERC-20 Overrides for rebasing                                         *
     ****************************************************************************************************************/
    // Rebase ERC20 balances and supply (stored in underlying)
    function totalSupply() public view virtual override(IERC20, ERC20) returns (uint256) {
        return _convertToShares(super.totalSupply(), Math.Rounding.Floor);
    }

    function balanceOf(address account) public view virtual override(IERC20, ERC20) returns (uint256) {
        return _convertToShares(super.balanceOf(account), Math.Rounding.Floor);
    }

    // Update ERC20 movements (labeled in rebasing, executed in underlying)
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(
            from,
            to,
            _convertToAssets(
                value,
                (
                    msg.sig == IERC4626.deposit.selector ||
                    msg.sig == IERC4626.redeem.selector ||
                    msg.sig == IERC1363Receiver.onTransferReceived.selector
                )
                    ? Math.Rounding.Floor
                    : Math.Rounding.Ceil
            )
        );
    }

    /****************************************************************************************************************
     *                                          ERC-4626 Conversion rates                                           *
     ****************************************************************************************************************/
    // underlying to rebasing
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual override returns (uint256) {
        (uint256 price, uint256 denom) = _getPrice();
        return assets.mulDiv(price, denom, rounding);
    }

    // rebasing to underlying
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual override returns (uint256) {
        (uint256 price, uint256 denom) = _getPrice();
        return shares.mulDiv(denom, price, rounding);
    }
}
