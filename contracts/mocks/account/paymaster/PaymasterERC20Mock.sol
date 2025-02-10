// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC4337Utils, PackedUserOperation} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {PaymasterERC20, IERC20} from "../../../account/paymaster/PaymasterERC20.sol";

abstract contract PaymasterERC20Mock is PaymasterERC20, Ownable {
    /// Note: this is for testing purpose only. Rate should be fetched from a trusted source (or signed).
    function _fetchDetails(
        PackedUserOperation calldata userOp,
        bytes32 /* userOpHash */
    )
        internal
        view
        virtual
        override
        returns (IERC20 token, uint48 validAfter, uint48 validUntil, uint256 tokenPrice, address guarantor)
    {
        bytes calldata paymasterData = ERC4337Utils.paymasterData(userOp);
        return (
            IERC20(address(bytes20(paymasterData[0x00:0x14]))),
            uint48(bytes6(paymasterData[0x14:0x1a])),
            uint48(bytes6(paymasterData[0x1a:0x20])),
            uint256(bytes32(paymasterData[0x20:0x40])),
            address(bytes20(paymasterData[0x40:0x54]))
        );
    }

    function _authorizeWithdraw() internal override onlyOwner {}
}
