// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IClaimIssuer, ITrustedIssuersRegistry} from "../../../../interfaces/IERC3643.sol";

/**
 * @dev Implementation of the ERC-3643 Trusted Issuers Registry: the claim issuers an {ERC3643IdentityRegistry}
 * accepts claims from, and the claim topics each of them is trusted for.
 *
 * Besides the topics of each issuer, the registry keeps the issuers of each topic, so
 * {getTrustedIssuersForClaimTopic} reads them directly instead of going through every issuer.
 *
 * The standard defines no access model. Derived contracts implement {_authorizeIssuersUpdate} to restrict
 * {addTrustedIssuer}, {removeTrustedIssuer} and {updateIssuerClaimTopics}:
 *
 * ```solidity
 * contract MyTrustedIssuersRegistry is ERC3643TrustedIssuersRegistry, Ownable {
 *     constructor(address initialOwner) Ownable(initialOwner) {}
 *
 *     function _authorizeIssuersUpdate() internal view override onlyOwner {}
 * }
 * ```
 *
 * NOTE: {ERC3643IdentityRegistry-isVerified} may query every issuer trusted for a topic, so its cost grows with
 * the number of issuers. Neither the number of issuers nor the number of topics per issuer is capped. Derived
 * contracts that need a bound can override {_addTrustedIssuer} and {_updateIssuerClaimTopics}.
 */
abstract contract ERC3643TrustedIssuersRegistry is ITrustedIssuersRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    EnumerableSet.AddressSet private _trustedIssuers;
    mapping(address issuer => EnumerableSet.UintSet) private _issuerClaimTopics;
    mapping(uint256 claimTopic => EnumerableSet.AddressSet) private _claimTopicIssuers;

    /// @dev The trusted issuer is not a valid address.
    error ERC3643InvalidTrustedIssuer(address issuer);

    /// @dev The trusted issuer is already registered.
    error ERC3643TrustedIssuerAlreadyRegistered(address issuer);

    /// @dev The trusted issuer is not registered.
    error ERC3643TrustedIssuerNotRegistered(address issuer);

    /// @dev The trusted issuer would be trusted for no claim topic.
    error ERC3643EmptyClaimTopics(address issuer);

    /// @inheritdoc ITrustedIssuersRegistry
    function getTrustedIssuers() public view virtual returns (IClaimIssuer[] memory) {
        return _asClaimIssuers(_trustedIssuers.values());
    }

    /// @inheritdoc ITrustedIssuersRegistry
    function isTrustedIssuer(address issuer) public view virtual returns (bool) {
        return _trustedIssuers.contains(issuer);
    }

    /**
     * @dev Returns the claim topics `trustedIssuer` is trusted for.
     *
     * NOTE: Returns an empty array if `trustedIssuer` is not registered.
     */
    function getTrustedIssuerClaimTopics(IClaimIssuer trustedIssuer) public view virtual returns (uint256[] memory) {
        return _issuerClaimTopics[address(trustedIssuer)].values();
    }

    /// @inheritdoc ITrustedIssuersRegistry
    function getTrustedIssuersForClaimTopic(uint256 claimTopic) public view virtual returns (IClaimIssuer[] memory) {
        return _asClaimIssuers(_claimTopicIssuers[claimTopic].values());
    }

    /// @inheritdoc ITrustedIssuersRegistry
    function hasClaimTopic(address issuer, uint256 claimTopic) public view virtual returns (bool) {
        return _issuerClaimTopics[issuer].contains(claimTopic);
    }

    /// @inheritdoc ITrustedIssuersRegistry
    function addTrustedIssuer(IClaimIssuer trustedIssuer, uint256[] calldata claimTopics) public virtual {
        _authorizeIssuersUpdate();
        require(
            _addTrustedIssuer(trustedIssuer, claimTopics),
            ERC3643TrustedIssuerAlreadyRegistered(address(trustedIssuer))
        );
    }

    /// @inheritdoc ITrustedIssuersRegistry
    function removeTrustedIssuer(IClaimIssuer trustedIssuer) public virtual {
        _authorizeIssuersUpdate();
        require(_removeTrustedIssuer(trustedIssuer), ERC3643TrustedIssuerNotRegistered(address(trustedIssuer)));
    }

    /// @inheritdoc ITrustedIssuersRegistry
    function updateIssuerClaimTopics(IClaimIssuer trustedIssuer, uint256[] calldata claimTopics) public virtual {
        _authorizeIssuersUpdate();
        require(
            _updateIssuerClaimTopics(trustedIssuer, claimTopics),
            ERC3643TrustedIssuerNotRegistered(address(trustedIssuer))
        );
    }

    /// @dev Reverts if the caller is not allowed to add, remove or update trusted issuers.
    function _authorizeIssuersUpdate() internal virtual;

    /**
     * @dev Registers `trustedIssuer` as trusted for `claimTopics`. Returns false if it was already registered.
     *
     * Requirements:
     *
     * * `trustedIssuer` must not be the zero address.
     * * `claimTopics` must not be empty.
     *
     * Emits a {TrustedIssuerAdded} event when the issuer is registered. Duplicated topics are stored once.
     */
    function _addTrustedIssuer(
        IClaimIssuer trustedIssuer,
        uint256[] memory claimTopics
    ) internal virtual returns (bool) {
        address issuer = address(trustedIssuer);
        require(issuer != address(0), ERC3643InvalidTrustedIssuer(address(0)));
        require(claimTopics.length > 0, ERC3643EmptyClaimTopics(issuer));
        if (!_trustedIssuers.add(issuer)) return false;
        _addIssuerClaimTopics(issuer, claimTopics);
        emit TrustedIssuerAdded(trustedIssuer, claimTopics);
        return true;
    }

    /**
     * @dev Removes `trustedIssuer` and the topics it is trusted for. Returns false if it was not registered.
     *
     * Emits a {TrustedIssuerRemoved} event when the issuer is removed.
     */
    function _removeTrustedIssuer(IClaimIssuer trustedIssuer) internal virtual returns (bool) {
        address issuer = address(trustedIssuer);
        if (!_trustedIssuers.remove(issuer)) return false;
        _clearIssuerClaimTopics(issuer);
        emit TrustedIssuerRemoved(trustedIssuer);
        return true;
    }

    /**
     * @dev Replaces the topics `trustedIssuer` is trusted for with `claimTopics`. Returns false if the issuer is
     * not registered.
     *
     * Requirements:
     *
     * * `claimTopics` must not be empty. Use {_removeTrustedIssuer} to stop trusting an issuer.
     *
     * Emits a {ClaimTopicsUpdated} event when the topics are replaced. Duplicated topics are stored once.
     */
    function _updateIssuerClaimTopics(
        IClaimIssuer trustedIssuer,
        uint256[] memory claimTopics
    ) internal virtual returns (bool) {
        address issuer = address(trustedIssuer);
        require(claimTopics.length > 0, ERC3643EmptyClaimTopics(issuer));
        if (!_trustedIssuers.contains(issuer)) return false;
        _clearIssuerClaimTopics(issuer);
        _addIssuerClaimTopics(issuer, claimTopics);
        emit ClaimTopicsUpdated(trustedIssuer, claimTopics);
        return true;
    }

    /// @dev Trusts `issuer` for each of `claimTopics`, in both directions of the index.
    function _addIssuerClaimTopics(address issuer, uint256[] memory claimTopics) private {
        EnumerableSet.UintSet storage issuerTopics = _issuerClaimTopics[issuer];
        for (uint256 i = 0; i < claimTopics.length; ++i) {
            if (issuerTopics.add(claimTopics[i])) _claimTopicIssuers[claimTopics[i]].add(issuer);
        }
    }

    /// @dev Stops trusting `issuer` for any topic, in both directions of the index.
    function _clearIssuerClaimTopics(address issuer) private {
        EnumerableSet.UintSet storage issuerTopics = _issuerClaimTopics[issuer];
        uint256[] memory claimTopics = issuerTopics.values();
        for (uint256 i = 0; i < claimTopics.length; ++i) {
            _claimTopicIssuers[claimTopics[i]].remove(issuer);
        }
        issuerTopics.clear();
    }

    /// @dev Reinterprets a list of addresses as a list of {IClaimIssuer}. Both have the same memory layout.
    function _asClaimIssuers(address[] memory issuers) private pure returns (IClaimIssuer[] memory result) {
        assembly ("memory-safe") {
            result := issuers
        }
    }
}
