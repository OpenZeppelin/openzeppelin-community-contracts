// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC4337Utils, PackedUserOperation} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PaymasterCore} from "./PaymasterCore.sol";

/**
 * @dev Extension of {PaymasterCore} that enables users to pay gas with ERC-20 tokens.
 *
 * To enable this feature, developers must implement the {fetchDetails} function:
 *
 * ```solidity
 * function _fetchDetails(
 *     PackedUserOperation calldata userOp,
 *     bytes32 userOpHash
 * ) internal view override returns (uint256 validationData, IERC20 token, uint256 tokenPrice) {
 *     // Implement logic to fetch the token, and token price from the userOp
 * }
 * ```
 */
abstract contract PaymasterERC20 is PaymasterCore {
    using ERC4337Utils for *;
    using Math for *;
    using SafeERC20 for IERC20;

    event UserOperationSponsored(
        bytes32 indexed userOpHash,
        address indexed user,
        uint256 tokenAmount,
        uint256 tokenPrice
    );

    /// @inheritdoc PaymasterCore
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal virtual override returns (bytes memory context, uint256 validationData) {
        (uint256 validationData_, IERC20 token, uint256 tokenPrice) = _fetchDetails(userOp, userOpHash);

        uint256 prefundAmount = _erc20Cost(maxCost, userOp.maxFeePerGas(), tokenPrice);
        (bool prefundSuccess, bytes memory prefundContext) = _prefund(
            userOp,
            userOpHash,
            userOp.sender,
            token,
            prefundAmount
        );

        return
            (validationData_ != ERC4337Utils.SIG_VALIDATION_FAILED && prefundSuccess)
                ? (
                    abi.encodePacked(userOpHash, token, prefundAmount, tokenPrice, userOp.sender, prefundContext),
                    validationData_
                )
                : (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);
    }

    /// @dev Prefunds the user operation.
    /// Takes userOp and userOpHash for maximun customization in overrides.
    function _prefund(
        PackedUserOperation calldata /* userOp */,
        bytes32 /* userOpHash */,
        address prefunder,
        IERC20 token,
        uint256 prefundAmount
    ) internal virtual returns (bool success, bytes memory context) {
        return (token.trySafeTransferFrom(prefunder, address(this), prefundAmount), bytes(""));
    }

    /// @inheritdoc PaymasterCore
    function _postOp(
        PostOpMode /* mode */,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal virtual override {
        bytes32 userOpHash = bytes32(context[0x00:0x20]); // essential for event emission
        address userOpSender = address(bytes20(context[0x74:0x88])); // essential for event emission
        IERC20 token = IERC20(address(bytes20(context[0x20:0x34]))); // essential for refund
        uint256 prefundAmount = uint256(bytes32(context[0x34:0x54])); // essential for refund
        uint256 tokenPrice = uint256(bytes32(context[0x54:0x74])); // essential for event emission
        bytes calldata prefundContext = context[0x88:];

        uint256 actualAmount = _erc20Cost(actualGasCost, actualUserOpFeePerGas, tokenPrice);
        _refund(userOpSender, token, prefundAmount, actualAmount, prefundContext);

        emit UserOperationSponsored(userOpHash, userOpSender, actualAmount, tokenPrice);
    }

    /// @dev Refunds the user operation.
    function _refund(
        address prefunder,
        IERC20 token,
        uint256 prefundAmount,
        uint256 actualAmount,
        bytes calldata /* prefundContext */
    ) internal virtual {
        token.safeTransfer(prefunder, prefundAmount - actualAmount);
    }

    /**
     * @dev Retrieves payment details for a user operation
     *
     * The values returned by this internal function are:
     * * `validationData`: ERC-4337 validation data, indicating success/failure and optional time validity (`validAfter`, `validUntil`).
     * * `token`: Address of the ERC-20 token used for payment to the paymaster.
     * * `tokenPrice`: Price of the token in native currency, scaled by `_tokenPriceDenominator()`.
     *
     * ==== Calculating the token price
     *
     * Given gas fees are paid in native currency, developers can use the `ERC20 price unit / native price unit` ratio to
     * calculate the price of an ERC20 token price in native currency. However, the token may have a different number of decimals
     * than the native currency. For a a generalized formula considering prices in USD and decimals, consider using:
     *
     * `(<ERC-20 token price in $> / 10**<ERC-20 decimals>) / (<Native token price in $> / 1e18) * _tokenPriceDenominator()`
     *
     * For example, suppose token is USDC ($1 with 6 decimals) and native currency is ETH (assuming $2524.86 with 18 decimals),
     * then each unit (1e-6) of USDC is worth `(1 / 1e6) / ((252486 / 1e2) / 1e18) = 396061563.8094785` wei. The `_tokenPriceDenominator()`
     * ensures precision by avoiding fractional value loss. (i.e. the 0.8094785 part).
     *
     */
    function _fetchDetails(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view virtual returns (uint256 validationData, IERC20 token, uint256 tokenPrice);

    /// @dev Over-estimates the cost of the post-operation logic.
    function _postOpCost() internal view virtual returns (uint256) {
        return 30_000;
    }

    /// @dev Denominator used for interpreting the `tokenPrice` returned by {_fetchDetails} as "fixed point".
    function _tokenPriceDenominator() internal view virtual returns (uint256) {
        return 1e18;
    }

    /// @dev Calculates the cost of the user operation in ERC-20 tokens.
    function _erc20Cost(uint256 cost, uint256 feePerGas, uint256 tokenPrice) internal view virtual returns (uint256) {
        return (cost + _postOpCost() * feePerGas).mulDiv(tokenPrice, _tokenPriceDenominator());
    }

    /// @dev Public function that allows the withdrawer to extract ERC-20 tokens resulting from gas payments.
    function withdrawTokens(IERC20 token, address recipient, uint256 amount) public virtual onlyWithdrawer {
        if (amount == type(uint256).max) amount = token.balanceOf(address(this));
        token.safeTransfer(recipient, amount);
    }
}
