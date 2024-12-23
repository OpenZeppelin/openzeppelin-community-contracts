// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {Account} from "../../account/Account.sol";

abstract contract AccountMock is Account {
    /// Validates a user operation with a boolean signature.
    function _rawSignatureValidation(
        bytes32 /* userOpHash */,
        bytes calldata signature
    ) internal pure override returns (bool) {
        return bytes1(signature[0:1]) == bytes1(0x01);
    }
}
