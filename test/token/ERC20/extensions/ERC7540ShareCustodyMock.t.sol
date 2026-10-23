// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC7540} from "@openzeppelin/community-contracts/token/ERC20/extensions/ERC7540.sol";
import {ERC7540AdminDeposit} from "@openzeppelin/community-contracts/token/ERC20/extensions/ERC7540AdminDeposit.sol";
import {ERC7540AdminRedeem} from "@openzeppelin/community-contracts/token/ERC20/extensions/ERC7540AdminRedeem.sol";
import {ERC7540DelayDeposit} from "@openzeppelin/community-contracts/token/ERC20/extensions/ERC7540DelayDeposit.sol";
import {ERC7540DelayRedeem} from "@openzeppelin/community-contracts/token/ERC20/extensions/ERC7540DelayRedeem.sol";

/// @dev Admin-fulfilled vault whose share custody addresses are stored, and therefore mutable.
contract ERC7540MutableCustodyMock is ERC7540AdminDeposit, ERC7540AdminRedeem {
    address private _origin;
    address private _destination;

    constructor(IERC20 asset_, address origin_, address destination_) ERC20("Mutable", "MUT") ERC7540(asset_) {
        _origin = origin_;
        _destination = destination_;
    }

    function setDepositShareOrigin(address origin_) public {
        _origin = origin_;
    }

    function setRedeemShareDestination(address destination_) public {
        _destination = destination_;
    }

    function fulfillDeposit(uint256 assets, uint256 shares, address controller) public {
        _fulfillDeposit(assets, shares, controller);
    }

    function fulfillRedeem(uint256 shares, uint256 assets, address controller) public {
        _fulfillRedeem(shares, assets, controller);
    }

    function _depositShareOrigin() internal view virtual override returns (address) {
        return _origin;
    }

    function _redeemShareDestination() internal view virtual override returns (address) {
        return _destination;
    }

    function _requestDeposit(
        uint256 assets,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540AdminDeposit) returns (uint256) {
        return super._requestDeposit(assets, controller, owner, requestId);
    }

    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540AdminRedeem) returns (uint256) {
        return super._requestRedeem(shares, controller, owner, requestId);
    }
}

/// @dev Delay vault whose share custody addresses are written by the constructor body, i.e. after the
/// ERC7540DelayDeposit and ERC7540DelayRedeem constructors have already read them. This is the shape the
/// modules' own NOTE describes as possibly escaping the constructor check.
contract ERC7540StorageCustodyDelayMock is ERC7540DelayDeposit, ERC7540DelayRedeem {
    address private _origin;
    address private _destination;

    constructor(IERC20 asset_, address origin_, address destination_) ERC20("Delay", "DLY") ERC7540(asset_) {
        _origin = origin_;
        _destination = destination_;
    }

    function depositShareOrigin() public view returns (address) {
        return _depositShareOrigin();
    }

    function redeemShareDestination() public view returns (address) {
        return _redeemShareDestination();
    }

    function clock() public view virtual override(ERC7540DelayDeposit, ERC7540DelayRedeem) returns (uint48) {
        return super.clock();
    }

    function CLOCK_MODE()
        public
        view
        virtual
        override(ERC7540DelayDeposit, ERC7540DelayRedeem)
        returns (string memory)
    {
        return super.CLOCK_MODE();
    }

    function _depositShareOrigin() internal view virtual override returns (address) {
        return _origin;
    }

    function _redeemShareDestination() internal view virtual override returns (address) {
        return _destination;
    }

    function _requestDeposit(
        uint256 assets,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540DelayDeposit) returns (uint256) {
        return super._requestDeposit(assets, controller, owner, requestId);
    }

    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540DelayRedeem) returns (uint256) {
        return super._requestRedeem(shares, controller, owner, requestId);
    }
}
