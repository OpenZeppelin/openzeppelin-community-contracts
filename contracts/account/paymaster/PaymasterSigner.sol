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
    using ERC4337Utils for *;

    bytes32 internal constant _USER_OPERATION_REQUEST =
        keccak256(
            "UserOperationRequest(address sender,uint256 nonce,bytes initCode,bytes callData,bytes32 accountGasLimits,uint256 paymasterVerificationGasLimit,uint256 preVerificationGas,bytes32 gasFees,uint48 validAfter,uint48 validUntil)"
        );

    /**
     * @dev Virtual function that returns the signable hash for a user operations. Given the `userOpHash`
     * contains the `paymasterAndData` itself, it's not possible to sign that value directly. Instead,
     * this function must be used to provide a custom mechanism to authorize an user operation.
     */
    function _signableUserOpHash(
        PackedUserOperation calldata userOp,
        uint48 validAfter,
        uint48 validUntil
    ) internal view virtual returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _USER_OPERATION_REQUEST,
                        userOp.sender,
                        userOp.nonce,
                        keccak256(userOp.initCode),
                        keccak256(userOp.callData),
                        userOp.accountGasLimits,
                        userOp.paymasterVerificationGasLimit(),
                        userOp.preVerificationGas,
                        userOp.gasFees,
                        validAfter,
                        validUntil
                    )
                )
            );
    }

    /**
     * @dev Internal validation of whether the paymaster is willing to pay for the user operation.
     * Returns the context to be passed to postOp and the validation data.
     *
     * NOTE: The `context` returned is `bytes(0)`. Developers overriding this function MUST
     * override {_postOp} to process the context passed along.
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 /* userOpHash */,
        uint256 /* maxCost */
    ) internal virtual override returns (bytes memory context, uint256 validationData) {
        (uint48 validUntil, uint48 validAfter, bytes calldata signature) = decodePaymasterUserOp(userOp);
        return (
            context,
            _rawSignatureValidation(_signableUserOpHash(userOp, validAfter, validUntil), signature).packValidationData(
                validUntil,
                validAfter
            )
        );
    }

    /// @dev Decodes the user operation's data from `paymasterAndData`.
    function decodePaymasterUserOp(
        PackedUserOperation calldata userOp
    ) public pure virtual returns (uint48 validAfter, uint48 validUntil, bytes calldata signature) {
        bytes calldata paymasterData = userOp.paymasterData();
        return (uint48(bytes6(paymasterData[0:6])), uint48(bytes6(paymasterData[6:12])), paymasterData[12:]);
    }

    function _postOp(
        PostOpMode /* mode */,
        bytes calldata /* context */,
        uint256 /* actualGasCost */,
        uint256 /* actualUserOpFeePerGas */
    ) internal virtual override {
        // No context for postop
    }
}
