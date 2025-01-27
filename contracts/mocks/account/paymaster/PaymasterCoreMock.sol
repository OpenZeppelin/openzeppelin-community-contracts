// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {PaymasterCore} from "../../../account/paymaster/PaymasterCore.sol";

contract PaymasterCoreMock is PaymasterCore {
    using ERC4337Utils for *;

    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 /* userOpHash */,
        uint256 /* requiredPreFund */
    ) internal virtual override returns (bytes memory context, uint256 validationData) {
        bytes calldata paymasterData = userOp.paymasterData();
        return (
            context,
            (bytes1(paymasterData[0:1]) == bytes1(0x01)).packValidationData(
                uint48(bytes6(paymasterData[1:7])),
                uint48(bytes6(paymasterData[7:13]))
            )
        );
    }

    function _postOp(
        PostOpMode /* mode */,
        bytes calldata context,
        uint256 /* actualGasCost */,
        uint256 /* actualUserOpFeePerGas */
    ) internal override {
        // No context for postop
    }

    // WARNING: No access control
    function deposit() external payable {
        _deposit();
    }

    // WARNING: No access control
    function addStake(uint32 unstakeDelaySec) external payable {
        _addStake(unstakeDelaySec);
    }
}
