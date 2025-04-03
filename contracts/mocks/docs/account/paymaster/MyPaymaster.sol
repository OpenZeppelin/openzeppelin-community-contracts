// contracts/MyPaymaster.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {PaymasterCore} from "../../../../account/paymaster/PaymasterCore.sol";

contract MyPaymaster is PaymasterCore, Ownable {
    constructor(address withdrawer) Ownable(withdrawer) {}

    /// @dev Paymaster user op validation logic
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 requiredPreFund
    ) internal override returns (bytes memory context, uint256 validationData) {
        // Custom validation logic
    }

    function _authorizeWithdraw() internal override onlyOwner {}
}
