// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IEntryPoint, IPaymaster, PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";

/**
 * @dev A simple ERC4337 paymaster implementation. This base implementation only includes the minimal logic to validate
 * and pay for user operations.
 *
 * Developers must implement the {PaymasterCore-_validatePaymasterUserOp} function to define the paymaster's validation
 * and payment logic. The `context` parameter is used to pass data between the validation and execution phases.
 *
 * The paymaster includes support to call the {IEntryPointStake} interface to manage the paymaster's deposits and stakes
 * through the internal functions {_deposit}, {_withdraw}, {_addStake}, {_unlockStake} and {_withdrawStake}.
 *
 * * Deposits are used to pay for user operations.
 * * Stakes are used to guarantee the paymaster's reputation and obtain more flexibility in accessing storage.
 *
 * NOTE: See [Paymaster's unstaked reputation rules](https://eips.ethereum.org/EIPS/eip-7562#unstaked-paymasters-reputation-rules)
 * for more details on the paymaster's storage access limitations.
 */
abstract contract PaymasterCore is IPaymaster {
    /// @dev Unauthorized call to the account.
    error PaymasterUnauthorized(address sender);

    /// @dev Revert if the caller is not the entry point.
    modifier onlyEntryPoint() {
        _checkEntryPoint();
        _;
    }

    /// @dev Canonical entry point for the account that forwards and validates user operations.
    function entryPoint() public view virtual returns (IEntryPoint) {
        return ERC4337Utils.ENTRYPOINT;
    }

    /// @inheritdoc IPaymaster
    function validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) public virtual onlyEntryPoint returns (bytes memory context, uint256 validationData) {
        return _validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    /// @inheritdoc IPaymaster
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost,
        uint256 actualUserOpFeePerGas
    ) public virtual onlyEntryPoint {
        _postOp(mode, context, actualGasCost, actualUserOpFeePerGas);
    }

    /**
     * @dev Internal validation of whether the paymaster is willing to pay for the user operation.
     * Returns the context to be passed to postOp and the validation data.
     *
     * The `requiredPreFund` is the amount the paymaster has to pay (in native tokens). It's calculated
     * as `requiredGas * userOp.maxFeePerGas`, where `required` gas can be calculated from the user operation
     * as `verificationGasLimit + callGasLimit + paymasterVerificationGasLimit + paymasterPostOpGasLimit + preVerificationGas`
     */
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 requiredPreFund
    ) internal virtual returns (bytes memory context, uint256 validationData);

    /**
     * @dev Handles post user operation execution logic. The caller must be the entry point.
     *
     * It receives the `context` returned by `_validatePaymasterUserOp`. Reverts by default
     * since the function is not called if no context is returned by {validatePaymasterUserOp}.
     *
     * NOTE: The `actualUserOpFeePerGas` is not `tx.gasprice`. A user operation can be bundled with other transactions
     * making the gas price of the user operation to differ.
     */
    function _postOp(
        PostOpMode /* mode */,
        bytes calldata /* context */,
        uint256 /* actualGasCost */,
        uint256 /* actualUserOpFeePerGas */
    ) internal virtual {}

    /// @dev Calls {IEntryPointStake-depositTo}.
    function _deposit(uint256 value) internal virtual {
        ERC4337Utils.depositTo(address(this), value);
    }

    /// @dev Calls {IEntryPointStake-withdrawTo}.
    function _withdraw(address payable to, uint256 value) internal virtual {
        ERC4337Utils.withdrawTo(to, value);
    }

    /// @dev Calls {IEntryPointStake-addStake}.
    function _addStake(uint256 value, uint32 unstakeDelaySec) internal virtual {
        ERC4337Utils.addStake(value, unstakeDelaySec);
    }

    /// @dev Calls {IEntryPointStake-unlockStake}.
    function _unlockStake() internal virtual {
        ERC4337Utils.unlockStake();
    }

    /// @dev Calls {IEntryPointStake-withdrawStake}.
    function _withdrawStake(address payable to) internal virtual {
        ERC4337Utils.withdrawStake(to);
    }

    /// @dev Ensures the caller is the {entrypoint}.
    function _checkEntryPoint() internal view virtual {
        address sender = msg.sender;
        if (sender != address(entryPoint())) {
            revert PaymasterUnauthorized(sender);
        }
    }
}
