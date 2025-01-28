// contracts/MyPaymaster.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PaymasterCore} from "../../../../account/paymaster/PaymasterCore.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";

contract MyPaymaster is PaymasterCore {
    /// @dev Paymaster user op validation logic
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 requiredPreFund
    ) internal override returns (bytes memory context, uint256 validationData) {
        // Custom validation logic
    }
}
