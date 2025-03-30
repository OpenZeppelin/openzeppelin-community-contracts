// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC4337Utils, PackedUserOperation} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PaymasterCore} from "./PaymasterCore.sol";
import {AbstractSigner} from "../../utils/cryptography/AbstractSigner.sol";

/**
 * @dev Extension of {PaymasterCore} that enables users to pay gas with ERC-20 tokens.
 */
abstract contract PaymasterERC20 is PaymasterCore {
    using ERC4337Utils for *;
    using Math for *;
    using SafeERC20 for IERC20;

    event UserOperationSponsored(
        bytes32 indexed userOpHash,
        address indexed user,
        address indexed guarantor,
        uint256 tokenAmount,
        uint256 tokenPrice,
        bool paidByGuarantor
    );

    // Over-estimations: ERC-20 balances/allowances may be cold and contracts may not be optimized
    uint256 private constant POST_OP_COST = 30_000;
    uint256 private constant POST_OP_COST_WITH_GUARANTOR = 45_000;

    /// @inheritdoc PaymasterCore
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal virtual override returns (bytes memory context, uint256 validationData) {
        (uint256 validationData_, IERC20 token, uint256 tokenPrice, address guarantor) = _fetchDetails(
            userOp,
            userOpHash
        );

        uint256 prefundAmount = (maxCost +
            (guarantor == address(0)).ternary(POST_OP_COST, POST_OP_COST_WITH_GUARANTOR) *
            userOp.maxFeePerGas()).mulDiv(tokenPrice, _tokenPriceDenominator());

        // if validation is obviously failed, don't even try to do the ERC-20 transfer
        return
            (validationData_ != ERC4337Utils.SIG_VALIDATION_FAILED &&
                token.trySafeTransferFrom(
                    guarantor == address(0) ? userOp.sender : guarantor,
                    address(this),
                    prefundAmount
                ))
                ? (
                    abi.encodePacked(userOpHash, token, prefundAmount, tokenPrice, userOp.sender, guarantor),
                    validationData_
                )
                : (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);
    }

    /// @inheritdoc PaymasterCore
    function _postOp(
        PostOpMode /* mode */,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal virtual override {
        bytes32 userOpHash = bytes32(context[0x00:0x20]);
        IERC20 token = IERC20(address(bytes20(context[0x20:0x34])));
        uint256 prefundAmount = uint256(bytes32(context[0x34:0x54]));
        uint256 tokenPrice = uint256(bytes32(context[0x54:0x74]));
        address user = address(bytes20(context[0x74:0x88]));
        address guarantor = address(bytes20(context[0x88:0x9C]));

        uint256 actualAmount = (actualGasCost +
            (guarantor == address(0)).ternary(POST_OP_COST, POST_OP_COST_WITH_GUARANTOR) *
            actualUserOpFeePerGas).mulDiv(tokenPrice, _tokenPriceDenominator());

        if (guarantor == address(0)) {
            token.safeTransfer(user, prefundAmount - actualAmount);
            emit UserOperationSponsored(userOpHash, user, address(0), actualAmount, tokenPrice, false);
        } else if (token.trySafeTransferFrom(user, address(this), actualAmount)) {
            token.safeTransfer(guarantor, prefundAmount);
            emit UserOperationSponsored(userOpHash, user, guarantor, actualAmount, tokenPrice, false);
        } else {
            token.safeTransfer(guarantor, prefundAmount - actualAmount);
            emit UserOperationSponsored(userOpHash, user, guarantor, actualAmount, tokenPrice, true);
        }
    }

    /**
     * @dev Internal function that returns the repayment details for a given user operation
     *
     * Returns values are
     * * `validationData`: standard ERC-4337 validation data. This allows to specify that the fetching was
     *   unsuccessful. If also includes `validAfter` and `validUntil` that can be used to restrict the time validity
     *   of the the information being passed (if the tokenPrice expires)
     * * `token`: the address of the ERC-20 token used for payment, by the user to the paymaster.
     * * `tokenPrice`: the price, in native currency, of the token being used for payments. This is a fixed point
     *    value which scaling is described by the {_tokenPriceDenominator} function.
     * * `guarantor`: the address of a guarantor that can advance the funds if a user doesn't have them, and will
     *   receive the tokens necessary for payment as part of the user operation execution. If the user doesn't get
     *   the funds, or doesn't approve them to the paymaster, then the guarantor will be the one paying the for the
     *   user operation.
     *
     * Example of token price:
     * Lets say the token used for payment is USDC (worth $1) and we are one ethereum mainnet, where the native
     * currency is ETH (worth $2524.86 in this example). Each USDC token is worth 0.0003960615638094785 ETH. Given
     * that USDC has 6 decimal places, and that each ETH is composed of 1e18 WEI, each USDC "unit" is worth
     * 396061563.8094785 WEI. With {_tokenPriceDenominator} being set to `1e18` (default value), then the `tokenPrice`
     * should be 396061563809478515454115840.
     *
     * General formula is:
     * (<ERC-20 token price in $> / 10**<ERC-20 decimals>)/(<Native token price in $> / 1e18) * <_tokenPriceDenominator>
     *
     * This function may be implemented in any number of ways, including
     * * Hardcoding the address of the token (only one token supported)
     * * Getting the price from an onchain oracle
     * * Getting the (signed) values through the userOp's paymasterData
     *
     * The paymaster can also decide to not support guarantors, and always return address(0) for that part.
     *
     * NOTE: If a guarantor is supported, make sure that it can't be used arbitrarily to pay operations.
     * Concretely, if the guarantor is extracted from the `userOp`, make sure that it provided explicit consent to
     * support that user operation, for example by verifying a signature.
     */
    function _fetchDetails(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view virtual returns (uint256 validationData, IERC20 token, uint256 tokenPrice, address guarantor);

    /// @dev Denominator used for interpreting the `tokenPrice` returned by {_fetchDetails} as "fixed point".
    function _tokenPriceDenominator() internal view virtual returns (uint256) {
        return 1e18;
    }

    /// @dev Public function that allows the withdrawer to extract ERC-20 tokens resulting from gas payments.
    function withdrawTokens(IERC20 token, address recipient, uint256 amount) public virtual onlyWithdrawer {
        if (amount == type(uint256).max) amount = token.balanceOf(address(this));
        token.safeTransfer(recipient, amount);
    }
}
