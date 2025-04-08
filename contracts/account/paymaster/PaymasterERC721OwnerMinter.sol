// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {ERC4337Utils, PackedUserOperation} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {PaymasterERC721Owner} from "./PaymasterERC721Owner.sol";

/**
 * @dev If a ERC721 enables the user to get sponsored transactions
 * How do we put the NFT on the user on the first place?
 * There is any way this Paymaster could sponsor the minting of an NFT?
 */
abstract contract PaymasterERC721OwnerMinter is PaymasterERC721Owner {
    bytes4 private _sponsoredSelector;

    constructor(IERC721 token_, bytes4 sponsoredSelector_) PaymasterERC721Owner(token_) {
        /// Can I check the token has the selector?
        _sponsoredSelector = sponsoredSelector_;
    }

    function sponsoredSelector() public view returns (bytes4) {
        return _sponsoredSelector;
    }

    /// @inheritdoc PaymasterERC721Owner
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 /* maxCost */
    ) internal virtual override returns (bytes memory context, uint256 validationData) {
        /// The userOp.sender get's sponsored under two conditions:
        /// 1. The userOp.sender has a balance of the token greater than 1.
        if (token().balanceOf(userOp.sender) != 0) {
            return (abi.encodePacked(userOpHash, userOp.sender), ERC4337Utils.SIG_VALIDATION_SUCCESS);
        }

        /// 2. The userOp is targeting the IERC721 token_ with the  _sponsoredSelector
        address target = address(bytes20(userOp.callData[0x00:0x20]));
        bytes4 selector = bytes4(userOp.callData[0x20:0x40]);
        if (target == address(token()) && selector == _sponsoredSelector) {
            return (abi.encodePacked(userOpHash, userOp.sender), ERC4337Utils.SIG_VALIDATION_SUCCESS);
        }

        return (bytes(""), ERC4337Utils.SIG_VALIDATION_FAILED);
    }

    /// @inheritdoc PaymasterERC721Owner
    function _postOp(
        PostOpMode /* mode */,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal virtual override {
        bytes32 userOpHash = bytes32(context[0x00:0x20]);
        address user = address(bytes20(context[0x20:0x34]));
        emit UserOperationSponsored(userOpHash, user);
    }
}
