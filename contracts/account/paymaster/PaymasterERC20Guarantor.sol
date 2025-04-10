// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC4337Utils, PackedUserOperation} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PaymasterERC20} from "./PaymasterERC20.sol";

/// @title PaymasterERC20Guarantor
/// @notice A paymaster that allows users to guarantee their user operations.
abstract contract PaymasterERC20Guarantor is PaymasterERC20 {
    using SafeERC20 for IERC20;

    event UserOperationGuaranteed(
        bytes32 indexed userOpHash,
        address indexed user,
        address indexed guarantor,
        uint256 prefundAmount
    );

    function _prefund(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        address /* prefunder */,
        IERC20 token,
        uint256 prefundAmount
    ) internal virtual override returns (bool success, bytes memory context) {
        (uint256 validationData_, address guarantor) = _fetchGuarantor(userOp);
        if (validationData_ == ERC4337Utils.SIG_VALIDATION_SUCCESS && guarantor != address(0)) {
            // If the Guarantor validation is successful, guarantor prefunds the user operation.
            (bool success_, ) = super._prefund(userOp, userOpHash, guarantor, token, prefundAmount);
            if (success_) {
                emit UserOperationGuaranteed(userOpHash, userOp.sender, guarantor, prefundAmount);
                return (success_, abi.encodePacked(guarantor));
            }
        }
        // If the Guarantor validation or guarantor payment is not successful, fallback to the user prefunding.
        return super._prefund(userOp, userOpHash, userOp.sender, token, prefundAmount);
    }

    function _refund(
        address userOpSender,
        IERC20 token,
        uint256 prefundAmount,
        uint256 actualAmount,
        bytes calldata prefundContext
    ) internal virtual override {
        if (prefundContext.length == 0) {
            // If there's no guarantor, fallback to the user refunding.
            super._refund(userOpSender, token, prefundAmount, actualAmount, prefundContext);
        } else {
            address guarantor = address(bytes20(prefundContext[0x00:0x20])); // Should we add more checks of the guarantor variable or is assumed to be right?
            // Attempt to debt the userOpSender the actualAmount into the paymaster
            if (token.trySafeTransferFrom(userOpSender, address(this), actualAmount)) {
                // If successful, pay back the guarantor the prefundAmount.
                token.safeTransfer(guarantor, prefundAmount);
            } else {
                // Otherwise, refund the guarantor the prefund remainder (he absorbs the actualAmount payment loss)
                super._refund(guarantor, token, prefundAmount, actualAmount, prefundContext);
            }
        }
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
