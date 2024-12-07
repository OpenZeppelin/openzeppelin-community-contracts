// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {AccountBase} from "../../account/draft-AccountBase.sol";

contract AccountBaseMock is AccountBase {
    /// Validates a user operation with a boolean signature.
    function _validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 /* userOpHash */
    ) internal pure override returns (uint256 validationData) {
        return
            bytes1(userOp.signature[0:1]) == bytes1(0x01)
                ? ERC4337Utils.SIG_VALIDATION_SUCCESS
                : ERC4337Utils.SIG_VALIDATION_FAILED;
    }

    function _userOpSignedHash(
        PackedUserOperation calldata /* userOp */,
        bytes32 userOpHash
    ) internal pure override returns (bytes32) {
        return userOpHash;
    }
}
