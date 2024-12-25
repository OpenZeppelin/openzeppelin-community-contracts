// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {IERC7579Validator, IERC7579Module, MODULE_TYPE_VALIDATOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";

/**
 * @dev ERC7579 Validator module.
 *
 * See {_isValidSignatureWithSender} for the signature validation logic.
 */
abstract contract ERC7579Validator is IERC7579Validator {
    /// @inheritdoc IERC7579Module
    function isModuleType(uint256 moduleTypeId) public pure virtual returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }

    /// @inheritdoc IERC7579Validator
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) public view virtual returns (uint256) {
        return
            _isValidSignatureWithSender(msg.sender, userOpHash, userOp.signature)
                ? ERC4337Utils.SIG_VALIDATION_SUCCESS
                : ERC4337Utils.SIG_VALIDATION_FAILED;
    }

    /// @inheritdoc IERC7579Validator
    function isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) public view virtual returns (bytes4) {
        return
            _isValidSignatureWithSender(sender, hash, signature)
                ? IERC1271.isValidSignature.selector
                : bytes4(0xffffffff);
    }

    /// @dev Validates a signature for a specific sender.
    function _isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual returns (bool);
}
