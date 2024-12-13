// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {AccountBase} from "../../account/draft-AccountBase.sol";

abstract contract AccountBaseMock is AccountBase {
    /// Validates a user operation with a boolean signature.
    function _validateSignature(
        bytes32 nestedEIP712Hash,
        bytes calldata signature
    ) internal pure override returns (bool) {
        return bytes1(signature[0:1]) == bytes1(0x01);
    }
}
