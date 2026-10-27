// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IClaimTopicsRegistry} from "../../../../interfaces/IERC3643.sol";

/**
 * @dev Implementation of the ERC-3643 Claim Topics Registry: the claim topics an identity must hold a valid
 * claim for to be verified by an {ERC3643IdentityRegistry}.
 *
 * The standard defines no access model. Derived contracts implement {_authorizeClaimTopicsUpdate} to restrict
 * {addClaimTopic} and {removeClaimTopic}:
 *
 * ```solidity
 * contract MyClaimTopicsRegistry is ERC3643ClaimTopicsRegistry, Ownable {
 *     constructor(address initialOwner) Ownable(initialOwner) {}
 *
 *     function _authorizeClaimTopicsUpdate() internal view override onlyOwner {}
 * }
 * ```
 *
 * NOTE: {ERC3643IdentityRegistry-isVerified} checks every registered topic, so its cost grows with the number of
 * topics. The number is not capped. Derived contracts that need a bound can override {_addClaimTopic}.
 */
abstract contract ERC3643ClaimTopicsRegistry is IClaimTopicsRegistry {
    using EnumerableSet for EnumerableSet.UintSet;

    EnumerableSet.UintSet private _claimTopics;

    /// @dev The claim topic is already registered.
    error ERC3643ClaimTopicAlreadyRegistered(uint256 claimTopic);

    /// @dev The claim topic is not registered.
    error ERC3643ClaimTopicNotRegistered(uint256 claimTopic);

    /// @inheritdoc IClaimTopicsRegistry
    function getClaimTopics() public view virtual returns (uint256[] memory) {
        return _claimTopics.values();
    }

    /// @inheritdoc IClaimTopicsRegistry
    function addClaimTopic(uint256 claimTopic) public virtual {
        _authorizeClaimTopicsUpdate();
        require(_addClaimTopic(claimTopic), ERC3643ClaimTopicAlreadyRegistered(claimTopic));
    }

    /// @inheritdoc IClaimTopicsRegistry
    function removeClaimTopic(uint256 claimTopic) public virtual {
        _authorizeClaimTopicsUpdate();
        require(_removeClaimTopic(claimTopic), ERC3643ClaimTopicNotRegistered(claimTopic));
    }

    /// @dev Reverts if the caller is not allowed to add or remove claim topics.
    function _authorizeClaimTopicsUpdate() internal virtual;

    /**
     * @dev Adds `claimTopic` to the required topics. Returns false if it was already registered.
     *
     * Emits a {ClaimTopicAdded} event when the topic is added.
     */
    function _addClaimTopic(uint256 claimTopic) internal virtual returns (bool) {
        bool added = _claimTopics.add(claimTopic);
        if (added) emit ClaimTopicAdded(claimTopic);
        return added;
    }

    /**
     * @dev Removes `claimTopic` from the required topics. Returns false if it was not registered.
     *
     * Emits a {ClaimTopicRemoved} event when the topic is removed.
     */
    function _removeClaimTopic(uint256 claimTopic) internal virtual returns (bool) {
        bool removed = _claimTopics.remove(claimTopic);
        if (removed) emit ClaimTopicRemoved(claimTopic);
        return removed;
    }
}
