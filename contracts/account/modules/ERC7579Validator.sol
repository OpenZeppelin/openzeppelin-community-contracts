// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC7579Module, IERC7579Validator, MODULE_TYPE_VALIDATOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
/**
 * @dev Abstract validator module for ERC-7579 accounts.
 *
 * This contract provides the base implementation for signature validation in ERC-7579 accounts.
 * Developers must implement the onInstall, onUninstall, and {_rawSignatureValidationWithSender}
 * functions in derived contracts to define the specific signature validation logic.
 *
 * Example usage:
 *
 * ```solidity
 * contract MyValidatorModule is ERC7579Validator {
 *     function onInstall(bytes calldata data) public {
 *         // Install logic here
 *     }
 *
 *     function onUninstall(bytes calldata data) public {
 *         // Uninstall logic here
 *     }
 *
 *     function _rawSignatureValidationWithSender(
 *         address sender,
 *         bytes32 hash,
 *         bytes calldata signature
 *     ) internal view override returns (bool) {
 *         // Signature validation logic here
 *     }
 * }
 * ```
 */
abstract contract ERC7579Validator is IERC7579Module, IERC7579Validator {
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
            _rawSignatureValidationWithSender(msg.sender, userOpHash, userOp.signature)
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
            _rawSignatureValidationWithSender(sender, hash, signature)
                ? IERC1271.isValidSignature.selector
                : bytes4(0xffffffff);
    }

    /**
     * @dev Internal version of {isValidSignatureWithSender} to be implemented by derived contracts.
     *
     * WARNING: Signature validation is a critical security function for smart accounts as it
     * determines whether operations can be executed on the account. Implementations must carefully
     * handle cryptographic verification to prevent unauthorized access. Thorough security review and
     * testing are required before deployment.
     */
    function _rawSignatureValidationWithSender(
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual returns (bool);
}
