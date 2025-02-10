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
    uint256 private constant POST_OP_COST_WITH_GUARANTOR = 50_000;

    /// @inheritdoc PaymasterCore
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal virtual override returns (bytes memory context, uint256 validationData) {
        (IERC20 token, uint48 validAfter, uint48 validUntil, uint256 tokenPrice, address guarantor) = _fetchDetails(
            userOp,
            userOpHash
        );

        uint256 prefundAmount = (maxCost +
            (guarantor == address(0)).ternary(POST_OP_COST, POST_OP_COST_WITH_GUARANTOR) *
            userOp.maxFeePerGas()).mulDiv(tokenPrice, _tokenPriceDenominator());

        return (
            abi.encodePacked(userOpHash, token, prefundAmount, tokenPrice, userOp.sender, guarantor),
            token
                .trySafeTransferFrom(guarantor == address(0) ? userOp.sender : guarantor, address(this), prefundAmount)
                .packValidationData(validAfter, validUntil)
        );
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
     * This may be implemented in any number of ways, including
     * * Hardcoding values (only one token supported)
     * * Getting the price from an onchain oracle
     * * Getting the (signed) values through the userOp's paymasterData
     *
     * The paymaster can also decide to not support guarantors, and always return address(0) for that part.
     */
    function _fetchDetails(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    )
        internal
        view
        virtual
        returns (IERC20 token, uint48 validAfter, uint48 validUntil, uint256 tokenPrice, address guarantor);

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
