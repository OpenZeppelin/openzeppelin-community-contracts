// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {ERC4337Utils, PackedUserOperation} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {PaymasterCore} from "./PaymasterCore.sol";

/**
 * @dev Extension of {PaymasterCore} that supports account based on ownership of an ERC-721 token
 */
abstract contract PaymasterNFT is PaymasterCore {
    IERC721 private _token;

    event PaymasterNFTTokenSet(IERC721 token);

    constructor(IERC721 token_) {
        _setToken(token_);
    }

    function token() public virtual returns (IERC721) {
        return _token;
    }

    function _setToken(IERC721 token_) internal virtual {
        _token = token_;
        emit PaymasterNFTTokenSet(token_);
    }

    /**
     * @dev Internal validation of whether the paymaster is willing to pay for the user operation.
     * Returns the context to be passed to postOp and the validation data.
     *
     * NOTE: The default `context` is `bytes(0)`. Developers that add a context when overriding this function MUST
     * also override {_postOp} to process the context passed along.
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 /* userOpHash */,
        uint256 /* maxCost */
    ) internal virtual override returns (bytes memory context, uint256 validationData) {
        return (
            bytes(""),
            token().balanceOf(userOp.sender) == 0
                ? ERC4337Utils.SIG_VALIDATION_FAILED
                : ERC4337Utils.SIG_VALIDATION_SUCCESS
        );
    }
}
