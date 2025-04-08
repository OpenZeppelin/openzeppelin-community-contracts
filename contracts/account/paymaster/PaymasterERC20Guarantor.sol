// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC4337Utils, PackedUserOperation} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {PaymasterERC20} from "./PaymasterERC20.sol";

/// @title PaymasterERC20Guarantor
/// @notice A paymaster that allows users to guarantee their user operations.
abstract contract PaymasterERC20Guarantor is PaymasterERC20 {
    event UserOperationGuaranteed(bytes32 indexed userOpHash, address indexed user, address indexed guarantor);

    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal virtual override returns (bytes memory context, uint256 validationData) {
        (uint256 validationData_, address guarantor) = _fetchGuarantor(userOp);
        if (validationData_ == ERC4337Utils.SIG_VALIDATION_SUCCESS && guarantor != address(0)) {
            emit UserOperationGuaranteed(userOpHash, userOp.sender, guarantor);
        }
        return super._validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    function _postOpCost() internal view virtual override returns (uint256) {
        return super._postOpCost() + 15_000;
    }

    function _fetchGuarantor(
        PackedUserOperation calldata userOp
    ) internal view virtual returns (uint256 validationData, address guarantor);
}
