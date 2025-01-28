// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {PaymasterCore} from "../../../account/paymaster/PaymasterCore.sol";

contract PaymasterCoreContextNoPostOpMock is PaymasterCore {
    using ERC4337Utils for *;

    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 /* userOpHash */,
        uint256 /* requiredPreFund */
    ) internal pure override returns (bytes memory context, uint256 validationData) {
        bytes calldata paymasterData = userOp.paymasterData();
        return (
            paymasterData,
            (bytes1(paymasterData[0:1]) == bytes1(0x01)).packValidationData(
                uint48(bytes6(paymasterData[1:7])),
                uint48(bytes6(paymasterData[7:13]))
            )
        );
    }

    // WARNING: No access control
    function deposit() external payable {
        _deposit();
    }
}

contract PaymasterCoreMock is PaymasterCoreContextNoPostOpMock {
    using ERC4337Utils for *;

    event PaymasterDataPostOp(bytes paymasterData);

    function _postOp(
        PostOpMode /* mode */,
        bytes calldata context,
        uint256 /* actualGasCost */,
        uint256 /* actualUserOpFeePerGas */
    ) internal override {
        emit PaymasterDataPostOp(context);
    }

    // WARNING: No access control
    function addStake(uint32 unstakeDelaySec) external payable {
        _addStake(unstakeDelaySec);
    }
}
