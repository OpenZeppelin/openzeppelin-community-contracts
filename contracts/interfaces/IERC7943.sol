// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Defines the ERC-7943 interface, the uRWA.
/// When interacting with specific token standards:
/// - For ERC-721 like (non-fungible) tokens 'amount' parameters typically represent a single token (i.e., 1).
/// - For ERC-20 like (fungible) tokens, 'tokenId' parameters are generally not applicable and should be set to 0.
interface IERC7943 is IERC165 {
    /// @notice Emitted when tokens are taken from one address and transferred to another.
    /// @param from The address from which tokens were taken.
    /// @param to The address to which seized tokens were transferred.
    /// @param tokenId The ID of the token being transferred.
    /// @param amount The amount seized.
    event ForcedTransfer(address indexed from, address indexed to, uint256 tokenId, uint256 amount);

    /// @notice Emitted when `setFrozen` is called, changing the frozen `amount` of `tokenId` tokens for `user`.
    /// @param user The address of the user whose tokens are being frozen.
    /// @param tokenId The ID of the token being frozen.
    /// @param amount The amount of tokens frozen after the change.
    event Frozen(address indexed user, uint256 indexed tokenId, uint256 amount);

    /// @notice Error reverted when a user is not allowed to interact.
    /// @param account The address of the user which is not allowed for interactions.
    error ERC7943NotAllowedUser(address account);

    /// @notice Error reverted when a transfer is not allowed due to restrictions in place.
    /// @param from The address from which tokens are being transferred.
    /// @param to The address to which tokens are being transferred.
    /// @param tokenId The ID of the token being transferred.
    /// @param amount The amount being transferred.
    error ERC7943NotAllowedTransfer(address from, address to, uint256 tokenId, uint256 amount);

    /// @notice Error reverted when a transfer is attempted from `user` with an `amount` of `tokenId` less or equal than its balance, but greater than its unfrozen balance.
    /// @param user The address holding the tokens.
    /// @param tokenId The ID of the token being transferred.
    /// @param amount The amount being transferred.
    /// @param unfrozen The amount of tokens that are unfrozen and available to transfer.
    error ERC7943InsufficientUnfrozenBalance(address user, uint256 tokenId, uint256 amount, uint256 unfrozen);

    /// @notice Takes tokens from one address and transfers them to another.
    /// @dev Requires specific authorization. Used for regulatory compliance or recovery scenarios.
    /// @param from The address from which `amount` is taken.
    /// @param to The address that receives `amount`.
    /// @param tokenId The ID of the token being transferred.
    /// @param amount The amount to force transfer.
    function forceTransfer(address from, address to, uint256 tokenId, uint256 amount) external;

    /// @notice Changes the frozen status of `amount` of `tokenId` tokens belonging to an `user`.
    /// This overwrites the current value, similar to an `approve` function.
    /// @dev Requires specific authorization. Frozen tokens cannot be transferred by the user.
    /// @param user The address of the user whose tokens are to be frozen/unfrozen.
    /// @param tokenId The ID of the token to freeze/unfreeze.
    /// @param amount The amount of tokens to freeze/unfreeze.
    function setFrozen(address user, uint256 tokenId, uint256 amount) external;

    /// @notice Checks the frozen status/amount of a specific `tokenId`.
    /// @param user The address of the user.
    /// @param tokenId The ID of the token.
    /// @return amount The amount of `tokenId` tokens currently frozen for `user`.
    function getFrozen(address user, uint256 tokenId) external view returns (uint256 amount);

    /// @notice Checks if a transfer is currently possible according to token rules. It enforces validations on the frozen tokens.
    /// @dev This may involve checks like allowlists, blocklists, transfer limits and other policy-defined restrictions.
    /// @param from The address sending tokens.
    /// @param to The address receiving tokens.
    /// @param tokenId The ID of the token being transferred.
    /// @param amount The amount being transferred.
    /// @return allowed True if the transfer is allowed, false otherwise.
    function isTransferAllowed(
        address from,
        address to,
        uint256 tokenId,
        uint256 amount
    ) external view returns (bool allowed);

    /// @notice Checks if a specific user is allowed to interact according to token rules.
    /// @dev This is often used for allowlist/KYC/KYB/AML checks.
    /// @param user The address to check.
    /// @return allowed True if the user is allowed, false otherwise.
    function isUserAllowed(address user) external view returns (bool allowed);
}
