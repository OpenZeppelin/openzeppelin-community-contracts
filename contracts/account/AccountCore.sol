// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation, IAccount, IEntryPoint} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {AbstractSigner} from "../utils/cryptography/AbstractSigner.sol";

/**
 * @dev A simple ERC4337 account implementation. This base implementation only includes the minimal logic to process
 * user operations.
 *
 * Developers must implement the {AccountCore-_signableUserOpHash} and {AbstractSigner-_rawSignatureValidation}
 * functions to define the account's validation logic.
 *
 * NOTE: This core account doesn't include any mechanism for performing arbitrary external calls. This is an essential
 * feature that all Account should have. We leave it up to the developers to implement the mechanism of their choice.
 * Common choices include ERC-6900, ERC-7579 and ERC-7821 (among others).
 *
 * IMPORTANT: Implementing a mechanism to validate signatures is a security-sensitive operation as it may allow an
 * attacker to bypass the account's security measures. Check out {SignerECDSA}, {SignerP256}, or {SignerRSA} for
 * digital signature validation implementations.
 */
abstract contract AccountCore is AbstractSigner, IAccount {
    /**
     * @dev Unauthorized call to the account.
     */
    error AccountUnauthorized(address sender);

    /**
     * @dev Revert if the caller is not the entry point or the account itself.
     */
    modifier onlyEntryPointOrSelf() {
        _checkEntryPointOrSelf();
        _;
    }

    /**
     * @dev Revert if the caller is not the entry point.
     */
    modifier onlyEntryPoint() {
        _checkEntryPoint();
        _;
    }

    /**
     * @dev Canonical entry point for the account that forwards and validates user operations.
     */
    function entryPoint() public view virtual returns (IEntryPoint) {
        return IEntryPoint(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    }

    /**
     * @dev Return the account nonce for the canonical sequence.
     */
    function getNonce() public view virtual returns (uint256) {
        return getNonce(0);
    }

    /**
     * @dev Return the account nonce for a given sequence (key).
     */
    function getNonce(uint192 key) public view virtual returns (uint256) {
        return entryPoint().getNonce(address(this), key);
    }

    /**
     * @inheritdoc IAccount
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) public virtual onlyEntryPoint returns (uint256) {
        uint256 validationData = _rawSignatureValidation(_signableUserOpHash(userOp, userOpHash), userOp.signature)
            ? ERC4337Utils.SIG_VALIDATION_SUCCESS
            : ERC4337Utils.SIG_VALIDATION_FAILED;
        _payPrefund(missingAccountFunds);
        return validationData;
    }

    /**
     * @dev Virtual function that returns the signable hash for a user operations. Some implementation may return
     * `userOpHash` while other may prefer a signer-friendly value such as an EIP-712 hash describing the `userOp`
     * details.
     */
    function _signableUserOpHash(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view virtual returns (bytes32);

    /**
     * @dev Sends the missing funds for executing the user operation to the {entrypoint}.
     * The `missingAccountFunds` must be defined by the entrypoint when calling {validateUserOp}.
     */
    function _payPrefund(uint256 missingAccountFunds) internal virtual {
        if (missingAccountFunds > 0) {
            (bool success, ) = payable(msg.sender).call{value: missingAccountFunds}("");
            success; // Silence warning. The entrypoint should validate the result.
        }
    }

    /**
     * @dev Ensures the caller is the {entrypoint}.
     */
    function _checkEntryPoint() internal view virtual {
        address sender = msg.sender;
        if (sender != address(entryPoint())) {
            revert AccountUnauthorized(sender);
        }
    }

    /**
     * @dev Ensures the caller is the {entrypoint} or the account itself.
     */
    function _checkEntryPointOrSelf() internal view virtual {
        address sender = msg.sender;
        if (sender != address(this) && sender != address(entryPoint())) {
            revert AccountUnauthorized(sender);
        }
    }

    /**
     * @dev Receive Ether.
     */
    receive() external payable virtual {}
}
