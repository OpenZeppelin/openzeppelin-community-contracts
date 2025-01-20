// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {IERC7579Validator, IERC7579Module, MODULE_TYPE_VALIDATOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @dev ERC7579 Validator module.
 *
 * See {_isValidSignatureWithSender} for the signature validation logic.
 */
abstract contract ERC7579Validator is IERC7579Validator {
    /// @inheritdoc IERC7579Module
    function isModuleType(uint256 moduleTypeId) public view virtual returns (bool) {
        return moduleTypeId == MODULE_TYPE_VALIDATOR;
    }

    /// @inheritdoc IERC7579Module
    function onInstall(bytes calldata data) public virtual {
        if (data.length > 0) Address.functionDelegateCall(address(this), data);
    }

    /// @inheritdoc IERC7579Module
    function onUninstall(bytes calldata data) public virtual {
        if (data.length > 0) Address.functionDelegateCall(address(this), data);
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

    /**
     * @dev Validates a signature for a specific sender.
     *
     * IMPORTANT: This function is used by the ERC-7579 Validator module to validate user operations. Make sure
     * the sender's associated storage follows https://eips.ethereum.org/EIPS/eip-7562[ERC-7562] validation rules
     * to ensure compatibility with the descentralized ERC-4337 mempool.
     */
    function _isValidSignatureWithSender(
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual returns (bool);
}
