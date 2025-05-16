// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7579Validator} from "./ERC7579Validator.sol";
import {ERC7913Utils} from "../../utils/cryptography/ERC7913Utils.sol";
import {IERC7579Module} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

/**
 * @dev Implementation of {ERC7579Validator} module using ERC-7913 signature verification.
 *
 * This validator allows ERC-7579 accounts to integrate with address-less cryptographic keys
 * through the ERC-7913 signature verification system. Each account can store its own ERC-7913
 * formatted signer (a concatenation of a verifier address and a key: `verifier || key`).
 *
 * This enables accounts to use signature schemes without requiring each key to have its own
 * Ethereum address.
 *
 * The validator implements two key functions from ERC-7579:
 *
 * * `validateUserOp`: Validates ERC-4337 user operations using ERC-7913 signatures
 * * `isValidSignatureWithSender`: Implements ERC-1271 signature verification via ERC-7913
 *
 * Example usage with an account:
 *
 * ```solidity
 * contract MyAccount is Account, AccountERC7579 {
 *     function initialize(address validator, bytes memory signerData) public initializer {
 *         // Install the validator module
 *         bytes memory initData = abi.encode(signerData);
 *         _installModule(MODULE_TYPE_VALIDATOR, validator, initData);
 *     }
 * }
 * ```
 *
 * Example of validator installation with a P256 key:
 *
 * ```solidity
 * // Address of the P256 verifier contract
 * address p256verifier = 0x123...;
 *
 * // P256 public key bytes
 * bytes memory p256PublicKey = 0x456...;
 *
 * // Combine into ERC-7913 signer format
 * bytes memory signerData = bytes.concat(abi.encodePacked(p256verifier), p256PublicKey);
 *
 * // Initialize the account with the validator and signer
 * account.initialize(address(new ERC7579SignatureValidator()), signerData);
 * ```
 */
contract ERC7579SignatureValidator is ERC7579Validator {
    mapping(address account => bytes signer) private _signers;

    /// @dev Emitted when the signer is set.
    event ERC7579SignatureValidatorSignerSet(address indexed account, bytes signer);

    /// @dev Thrown when the signer length is less than 20 bytes.
    error ERC7579SignatureValidatorInvalidSignerLength();

    /// @dev Return the ERC-7913 signer (i.e. `verifier || key`).
    function signer(address account) public view virtual returns (bytes memory) {
        return _signers[account];
    }

    /**
     * @dev See {IERC7579Module-onInstall}.
     *
     * NOTE: An account can only call onInstall once. If called directly by the account,
     * the signer will be set to the provided data. Future installations will behave as a no-op.
     */
    function onInstall(bytes calldata data) public virtual {
        if (signer(msg.sender).length == 0) {
            setSigner(data);
        }
    }

    /**
     * @dev See {IERC7579Module-onUninstall}.
     *
     * WARNING: The signer's key will be removed if the account calls this function, potentially
     * making the account unusable. As an account operator, make sure to uninstall to a predefined path
     * in your account that properly handles side effects of uninstallation.  See {AccountERC7579-uninstallModule}.
     */
    function onUninstall(bytes calldata) public virtual {
        _setSigner(msg.sender, "");
    }

    /// @dev Sets the ERC-7913 signer (i.e. `verifier || key`) for the calling account.
    function setSigner(bytes memory signer_) public virtual {
        require(signer_.length >= 20, ERC7579SignatureValidatorInvalidSignerLength());
        _setSigner(msg.sender, signer_);
    }

    /// @dev Internal version of {setSigner} that takes an `account` as argument without validating `signer_`.
    function _setSigner(address account, bytes memory signer_) internal virtual {
        _signers[account] = signer_;
        emit ERC7579SignatureValidatorSignerSet(account, signer_);
    }

    /**
     * @dev See {ERC7579Validator-_rawSignatureValidationWithSender}.
     *
     * Validates a `signature` using ERC-7913 verification.
     *
     * This base implementation ignores the `sender` parameter and validates using
     * the account's stored signer. Derived contracts can override this to implement
     * custom validation logic based on the sender.
     */
    function _rawSignatureValidationWithSender(
        address /* sender */,
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        return ERC7913Utils.isValidSignatureNow(signer(msg.sender), hash, signature);
    }
}
