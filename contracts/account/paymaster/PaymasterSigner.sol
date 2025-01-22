// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {PaymasterCore} from "./PaymasterCore.sol";
import {AbstractSigner} from "../../utils/cryptography/AbstractSigner.sol";

/**
 * @dev Extension of {PaymasterCore} that adds signature validation. See {SignerECDSA}, {SignerP256} or {SignerRSA}.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyPaymasterECDSASigner is PaymasterSigner, SignerECDSA {
 *     constructor() EIP712("MyPaymasterECDSASigner", "1") {
 *       // Will revert if the signer is already initialized
 *       _initializeSigner(signerAddr);
 *     }
 * }
 * ```
 */
abstract contract PaymasterSigner is PaymasterCore, EIP712, AbstractSigner {
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
     * @dev Internal validation of whether the paymaster is willing to pay for the user operation.
     * Returns the context to be passed to postOp and the validation data.
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 /* maxCost */
    ) internal virtual override returns (bytes memory context, uint256 validationData) {
        return (
            context,
            _rawSignatureValidation(_signableUserOpHash(userOp, userOpHash), userOp.signature)
                ? ERC4337Utils.SIG_VALIDATION_SUCCESS
                : ERC4337Utils.SIG_VALIDATION_FAILED
        );
    }
}
