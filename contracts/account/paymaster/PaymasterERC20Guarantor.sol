// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC4337Utils, PackedUserOperation} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PaymasterERC20} from "./PaymasterERC20.sol";

/// @title PaymasterERC20Guarantor
/// @notice A paymaster that allows users to guarantee their user operations.
abstract contract PaymasterERC20Guarantor is PaymasterERC20 {
    using SafeERC20 for IERC20;

    event UserOperationGuaranteed(bytes32 indexed userOpHash, address indexed user, address indexed guarantor);

    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal virtual override returns (bytes memory context, uint256 validationData) {
        // emit additional `UserOperationGuaranteed` in case there is a guarantor, default to inherited behavior otherwise.
        (uint256 validationData_, address guarantor) = _fetchGuarantor(userOp);
        if (validationData_ == ERC4337Utils.SIG_VALIDATION_SUCCESS && guarantor != address(0)) {
            emit UserOperationGuaranteed(userOpHash, userOp.sender, guarantor);
        }

        return super._validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    function _postOp(
        PostOpMode /* mode */,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal virtual override {
        (
            bytes32 userOpHash,
            IERC20 token,
            uint256 prefundAmount,
            uint256 tokenPrice,
            address userOpSender,
            address prefundPayer
        ) = _decodeContext(context);
        uint256 actualAmount = _erc20Cost(actualGasCost, actualUserOpFeePerGas, tokenPrice);

        // Handle guarantor re-payment in case there is such.
        if (prefundPayer == userOpSender) {
            token.safeTransfer(userOpSender, prefundAmount - actualAmount);
        }
        // Attempt to pay the actualAmount from the userOpSender to this paymaster.
        else if (token.trySafeTransferFrom(userOpSender, address(this), actualAmount)) {
            // If successful, pay back the prefundAmount to the guarantor.
            token.safeTransfer(prefundPayer, prefundAmount);
        } else {
            // Otherwise, refund the prefund remainder to the guarantor.
            token.safeTransfer(prefundPayer, prefundAmount - actualAmount);
        }

        emit UserOperationSponsored(userOpHash, userOpSender, actualAmount, tokenPrice);
    }

    function _prefundPayer(PackedUserOperation calldata userOp) internal view virtual override returns (address) {
        (uint256 validationData, address guarantor) = _fetchGuarantor(userOp);
        return
            (validationData == ERC4337Utils.SIG_VALIDATION_SUCCESS && guarantor != address(0))
                ? guarantor
                : userOp.sender;
    }

    function _postOpCost() internal view virtual override returns (uint256) {
        return super._postOpCost() + 15_000;
    }

    /**
     * @dev Fetches the guarantor address and validation data from the user operation.
     * Must be implemented in order to correctly enable guarantor functionality.
     */
    function _fetchGuarantor(
        PackedUserOperation calldata userOp
    ) internal view virtual returns (uint256 validationData, address guarantor);
}
