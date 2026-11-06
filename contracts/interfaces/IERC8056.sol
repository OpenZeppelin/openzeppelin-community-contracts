// SPDX-License-Identifier: MIT

pragma solidity >=0.8.4;

/**
 * @dev Interface of the ERC-8056 Scaled UI Amount extension for ERC-20 tokens, as defined in
 * https://eips.ethereum.org/EIPS/eip-8056[ERC-8056].
 *
 * NOTE: The ERC-165 identifier for this interface is `0xa60bf13d`.
 */
interface IScaledUIAmount {
    /// @dev Emitted when the UI multiplier is updated.
    event UIMultiplierUpdated(uint256 oldMultiplier, uint256 newMultiplier, uint256 effectiveAtTimestamp);

    /// @dev OPTIONAL: Emitted during a token transfer with the UI-adjusted amount.
    event TransferWithUIAmount(address indexed from, address indexed to, uint256 amount, uint256 uiAmount);

    /// @dev OPTIONAL: Emitted when a scheduled UI multiplier update is cancelled or superseded.
    event UIMultiplierUpdateCancelled(uint256 cancelledMultiplier, uint256 cancelledEffectiveAt);

    /// @dev Returns the current UI multiplier. Multiplier is represented with 18 decimals (1e18 = 1.0).
    function uiMultiplier() external view returns (uint256);
}

/**
 * @dev Required extension of {IScaledUIAmount} that exposes a pending UI multiplier that has been scheduled but has
 * not yet taken effect.
 *
 * NOTE: The ERC-165 identifier for this interface is `0x4bd27648`.
 */
interface IScaledUIAmountNewUIMultiplier {
    /// @dev Returns the pending UI multiplier scheduled to take effect at {effectiveAt}.
    /// Multiplier is represented with 18 decimals (1e18 = 1.0).
    function newUIMultiplier() external view returns (uint256);

    /// @dev Returns the timestamp at which the pending multiplier becomes effective.
    function effectiveAt() external view returns (uint256);
}

/**
 * @dev Optional extension of {IScaledUIAmount} with onchain conversion helpers.
 *
 * NOTE: The ERC-165 identifier for this interface is `0x57854fc3`.
 */
interface IScaledUIAmountConversion {
    /// @dev Converts a raw token amount to UI amount.
    function toUIAmount(uint256 rawAmount) external view returns (uint256);

    /// @dev Converts a UI amount to raw token amount.
    function fromUIAmount(uint256 uiAmount) external view returns (uint256);
}

/**
 * @dev Optional extension of {IScaledUIAmount} with onchain UI balance queries.
 *
 * NOTE: The ERC-165 identifier for this interface is `0xd890fd71`.
 */
interface IScaledUIAmountBalances {
    /// @dev Returns the UI-adjusted balance of an account.
    function balanceOfUI(address account) external view returns (uint256);

    /// @dev Returns the UI-adjusted total supply.
    function totalSupplyUI() external view returns (uint256);
}
