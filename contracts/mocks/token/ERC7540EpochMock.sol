// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7540} from "../../token/ERC20/extensions/ERC7540.sol";
import {ERC7540EpochDeposit} from "../../token/ERC20/extensions/ERC7540EpochDeposit.sol";
import {ERC7540EpochRedeem} from "../../token/ERC20/extensions/ERC7540EpochRedeem.sol";

abstract contract ERC7540EpochMock is ERC7540EpochDeposit, ERC7540EpochRedeem {
    function _requestDeposit(
        uint256 assets,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540EpochDeposit) returns (uint256) {
        return super._requestDeposit(assets, controller, owner, requestId);
    }

    function _requestRedeem(
        uint256 shares,
        address controller,
        address owner,
        uint256 requestId
    ) internal virtual override(ERC7540, ERC7540EpochRedeem) returns (uint256) {
        return super._requestRedeem(shares, controller, owner, requestId);
    }

    function _requestQueueLimit()
        internal
        view
        virtual
        override(ERC7540EpochDeposit, ERC7540EpochRedeem)
        returns (uint256)
    {
        return super._requestQueueLimit();
    }
}
