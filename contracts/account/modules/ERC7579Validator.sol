// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7579Module} from "./ERC7579Module.sol";
import {IERC7579Validator, MODULE_TYPE_VALIDATOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
/**
 * @dev Abstract validator module for ERC-7579 accounts.
 *
 * This contract provides the base implementation for signature validation in ERC-7579 accounts.
 * Developers must implement the onInstall, onUninstall, and {_isValidSignatureWithSender} function in derived contracts to
 * define the specific signature validation logic.
 *
 * Example usage:
 *
 * ```solidity
 * contract MyValidatorModule is ERC7579Validator {
 *     function onInstall(bytes calldata data) public override {
 *         // Install logic here
 *         ...
 *         super.onInstall(data);
 *     }
 *
 *     function onUninstall(bytes calldata data) public override {
 *         // Uninstall logic here
 *         ...
 *         super.onUninstall(data);
 *     }
 *
 *     function _isValidSignatureWithSender(
 *         address sender,
 *         bytes32 hash,
 *         bytes calldata signature
 *     ) internal view override returns (bool) {
 *         // Signature validation logic here
 *     }
 * }
 * ```
 */
abstract contract ERC7579Validator is ERC7579Module(MODULE_TYPE_VALIDATOR), IERC7579Validator {
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

    /// @dev Internal version of {isValidSignatureWithSender} to be implemented by derived contracts.
    function _isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual returns (bool);
}
