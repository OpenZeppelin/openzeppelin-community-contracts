// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {PaymasterCore} from "../../../account/paymaster/PaymasterCore.sol";

abstract contract PaymasterCoreContextNoPostOpMock is PaymasterCore, Ownable {
    using ERC4337Utils for *;

    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 /* userOpHash */,
        uint256 /* requiredPreFund */
    ) internal pure override returns (bytes memory context, uint256 validationData) {
        bytes calldata paymasterData = userOp.paymasterData();
        return (
            paymasterData,
            (bytes1(paymasterData) == bytes1(0x01)).packValidationData(
                uint48(bytes6(paymasterData[1:7])),
                uint48(bytes6(paymasterData[7:13]))
            )
        );
    }

    function _authorizeWithdraw() internal override onlyOwner {}
}

abstract contract PaymasterCoreMock is PaymasterCoreContextNoPostOpMock {
    event PaymasterDataPostOp(bytes paymasterData);

    function _postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) internal override {
        emit PaymasterDataPostOp(context);
        super._postOp(mode, context, actualGasCost, actualUserOpFeePerGas);
    }
}
