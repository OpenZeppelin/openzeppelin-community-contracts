// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {LowLevelCall} from "@openzeppelin/contracts/utils/LowLevelCall.sol";
import {
    IClaimIssuer,
    IClaimTopicsRegistry,
    IIdentity,
    IIdentityRegistry,
    IIdentityRegistryStorage,
    ITrustedIssuersRegistry
} from "../../../../interfaces/IERC3643.sol";
import {IERC735, IERC735ClaimIssuer} from "../../../../interfaces/IERC735.sol";

/**
 * @dev Implementation of the ERC-3643 Identity Registry: the registry an ERC-3643 token asks whether a wallet
 * may hold its tokens.
 *
 * Identities are kept in an {IIdentityRegistryStorage} (e.g. {ERC3643IdentityRegistryStorage}) that must bind
 * this registry before it can register identities. A wallet is verified when its identity holds, for every
 * topic of the {IClaimTopicsRegistry}, a valid claim from an issuer the {ITrustedIssuersRegistry} trusts for
 * that topic.
 *
 * Claims are checked by {_isClaimValid}, which follows the ERC-735 claim holder model by default. Derived
 * contracts override it to support other identity systems.
 *
 * The standard defines no access model. Derived contracts implement {_authorizeIdentityUpdate} to restrict the
 * identity management functions and {_authorizeRegistryUpdate} to restrict the registry setters:
 *
 * ```solidity
 * contract MyIdentityRegistry is ERC3643IdentityRegistry, AccessControl {
 *     bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");
 *
 *     constructor(
 *         address identityStorage,
 *         address trustedIssuersRegistry,
 *         address claimTopicsRegistry,
 *         address admin
 *     ) ERC3643IdentityRegistry(identityStorage, trustedIssuersRegistry, claimTopicsRegistry) {
 *         _grantRole(DEFAULT_ADMIN_ROLE, admin);
 *     }
 *
 *     function _authorizeIdentityUpdate() internal view override onlyRole(AGENT_ROLE) {}
 *
 *     function _authorizeRegistryUpdate() internal view override onlyRole(DEFAULT_ADMIN_ROLE) {}
 * }
 * ```
 */
abstract contract ERC3643IdentityRegistry is IIdentityRegistry {
    IIdentityRegistryStorage private _identityStorage;
    ITrustedIssuersRegistry private _issuersRegistry;
    IClaimTopicsRegistry private _topicsRegistry;

    /// @dev The identity registry storage is the zero address.
    error ERC3643MissingIdentityRegistryStorage();

    /// @dev The trusted issuers registry is the zero address.
    error ERC3643MissingTrustedIssuersRegistry();

    /// @dev The claim topics registry is the zero address.
    error ERC3643MissingClaimTopicsRegistry();

    /// @dev The batch arrays have different lengths.
    error ERC3643InvalidArrayLength();

    /// @dev Sets the identity registry storage, the trusted issuers registry and the claim topics registry.
    constructor(address identityStorage_, address trustedIssuersRegistry_, address claimTopicsRegistry_) {
        _setIdentityRegistryStorage(identityStorage_);
        _setTrustedIssuersRegistry(trustedIssuersRegistry_);
        _setClaimTopicsRegistry(claimTopicsRegistry_);
    }

    /// @inheritdoc IIdentityRegistry
    function identityStorage() public view virtual returns (IIdentityRegistryStorage) {
        return _identityStorage;
    }

    /// @inheritdoc IIdentityRegistry
    function issuersRegistry() public view virtual returns (ITrustedIssuersRegistry) {
        return _issuersRegistry;
    }

    /// @inheritdoc IIdentityRegistry
    function topicsRegistry() public view virtual returns (IClaimTopicsRegistry) {
        return _topicsRegistry;
    }

    /// @inheritdoc IIdentityRegistry
    function contains(address account) public view virtual returns (bool) {
        return address(identity(account)) != address(0);
    }

    /// @inheritdoc IIdentityRegistry
    function identity(address account) public view virtual returns (IIdentity) {
        return identityStorage().storedIdentity(account);
    }

    /// @inheritdoc IIdentityRegistry
    function investorCountry(address account) public view virtual returns (uint16) {
        return identityStorage().storedInvestorCountry(account);
    }

    /**
     * @dev Returns whether `account` has an identity that holds, for every required claim topic, a claim that
     * {_isClaimValid} accepts from an issuer trusted for that topic.
     *
     * A registered wallet is verified when no claim topic is required. A topic with no trusted issuer cannot be
     * satisfied.
     */
    function isVerified(address account) public view virtual returns (bool) {
        IIdentity userIdentity = identity(account);
        if (address(userIdentity) == address(0)) return false;

        uint256[] memory claimTopics = topicsRegistry().getClaimTopics();
        ITrustedIssuersRegistry trustedIssuers = issuersRegistry();
        for (uint256 i = 0; i < claimTopics.length; ++i) {
            if (
                !_hasValidClaim(
                    userIdentity,
                    claimTopics[i],
                    trustedIssuers.getTrustedIssuersForClaimTopic(claimTopics[i])
                )
            ) {
                return false;
            }
        }
        return true;
    }

    /// @inheritdoc IIdentityRegistry
    function setIdentityRegistryStorage(address identityRegistryStorage) public virtual {
        _authorizeRegistryUpdate();
        _setIdentityRegistryStorage(identityRegistryStorage);
    }

    /// @inheritdoc IIdentityRegistry
    function setTrustedIssuersRegistry(address trustedIssuersRegistry) public virtual {
        _authorizeRegistryUpdate();
        _setTrustedIssuersRegistry(trustedIssuersRegistry);
    }

    /// @inheritdoc IIdentityRegistry
    function setClaimTopicsRegistry(address claimTopicsRegistry) public virtual {
        _authorizeRegistryUpdate();
        _setClaimTopicsRegistry(claimTopicsRegistry);
    }

    /// @inheritdoc IIdentityRegistry
    function registerIdentity(address account, IIdentity userIdentity, uint16 country) public virtual {
        _authorizeIdentityUpdate();
        _registerIdentity(account, userIdentity, country);
    }

    /// @inheritdoc IIdentityRegistry
    function batchRegisterIdentity(
        address[] calldata accounts,
        IIdentity[] calldata identities,
        uint16[] calldata countries
    ) public virtual {
        _authorizeIdentityUpdate();
        require(
            accounts.length == identities.length && accounts.length == countries.length,
            ERC3643InvalidArrayLength()
        );
        for (uint256 i = 0; i < accounts.length; ++i) {
            _registerIdentity(accounts[i], identities[i], countries[i]);
        }
    }

    /// @inheritdoc IIdentityRegistry
    function deleteIdentity(address account) public virtual {
        _authorizeIdentityUpdate();
        _deleteIdentity(account);
    }

    /// @inheritdoc IIdentityRegistry
    function updateCountry(address account, uint16 country) public virtual {
        _authorizeIdentityUpdate();
        _updateCountry(account, country);
    }

    /// @inheritdoc IIdentityRegistry
    function updateIdentity(address account, IIdentity userIdentity) public virtual {
        _authorizeIdentityUpdate();
        _updateIdentity(account, userIdentity);
    }

    /// @dev Reverts if the caller is not allowed to register, delete or update identities.
    function _authorizeIdentityUpdate() internal virtual;

    /// @dev Reverts if the caller is not allowed to replace the identity storage or the registries.
    function _authorizeRegistryUpdate() internal virtual;

    /**
     * @dev Sets the identity registry storage.
     *
     * Emits an {IdentityStorageSet} event.
     */
    function _setIdentityRegistryStorage(address identityRegistryStorage) internal virtual {
        require(identityRegistryStorage != address(0), ERC3643MissingIdentityRegistryStorage());
        _identityStorage = IIdentityRegistryStorage(identityRegistryStorage);
        emit IdentityStorageSet(identityRegistryStorage);
    }

    /**
     * @dev Sets the trusted issuers registry.
     *
     * Emits a {TrustedIssuersRegistrySet} event.
     */
    function _setTrustedIssuersRegistry(address trustedIssuersRegistry) internal virtual {
        require(trustedIssuersRegistry != address(0), ERC3643MissingTrustedIssuersRegistry());
        _issuersRegistry = ITrustedIssuersRegistry(trustedIssuersRegistry);
        emit TrustedIssuersRegistrySet(trustedIssuersRegistry);
    }

    /**
     * @dev Sets the claim topics registry.
     *
     * Emits a {ClaimTopicsRegistrySet} event.
     */
    function _setClaimTopicsRegistry(address claimTopicsRegistry) internal virtual {
        require(claimTopicsRegistry != address(0), ERC3643MissingClaimTopicsRegistry());
        _topicsRegistry = IClaimTopicsRegistry(claimTopicsRegistry);
        emit ClaimTopicsRegistrySet(claimTopicsRegistry);
    }

    /**
     * @dev Stores `userIdentity` and `country` for `account` in the identity storage.
     *
     * Emits an {IdentityRegistered} event.
     */
    function _registerIdentity(address account, IIdentity userIdentity, uint16 country) internal virtual {
        identityStorage().addIdentityToStorage(account, userIdentity, country);
        emit IdentityRegistered(account, userIdentity);
    }

    /**
     * @dev Removes the identity of `account` from the identity storage.
     *
     * Emits an {IdentityRemoved} event.
     */
    function _deleteIdentity(address account) internal virtual {
        IIdentity oldIdentity = identity(account);
        identityStorage().removeIdentityFromStorage(account);
        emit IdentityRemoved(account, oldIdentity);
    }

    /**
     * @dev Replaces the country of `account` in the identity storage.
     *
     * Emits a {CountryUpdated} event.
     */
    function _updateCountry(address account, uint16 country) internal virtual {
        identityStorage().modifyStoredInvestorCountry(account, country);
        emit CountryUpdated(account, country);
    }

    /**
     * @dev Replaces the identity of `account` in the identity storage.
     *
     * Emits an {IdentityUpdated} event.
     */
    function _updateIdentity(address account, IIdentity userIdentity) internal virtual {
        IIdentity oldIdentity = identity(account);
        identityStorage().modifyStoredIdentity(account, userIdentity);
        emit IdentityUpdated(oldIdentity, userIdentity);
    }

    /**
     * @dev Returns whether `userIdentity` holds a claim for `claimTopic` that {_isClaimValid} accepts from one of
     * `trustedIssuers`.
     */
    function _hasValidClaim(
        IIdentity userIdentity,
        uint256 claimTopic,
        IClaimIssuer[] memory trustedIssuers
    ) private view returns (bool) {
        for (uint256 i = 0; i < trustedIssuers.length; ++i) {
            if (_isClaimValid(userIdentity, trustedIssuers[i], claimTopic)) return true;
        }
        return false;
    }

    /**
     * @dev Returns whether `userIdentity` holds a valid claim for `claimTopic` signed by `issuer`.
     *
     * By default, `userIdentity` is an {IERC735} claim holder. The claim is looked up by its ERC-735 identifier
     * `keccak256(abi.encode(issuer, claimTopic))` and must report `claimTopic` and `issuer`. The issuer is then
     * asked to confirm it through {IERC735ClaimIssuer-isClaimValid}. An identity or an issuer that reverts or
     * answers anything other than `true` makes the claim invalid.
     *
     * Override to support identities or claims in another format.
     */
    function _isClaimValid(
        IIdentity userIdentity,
        IClaimIssuer issuer,
        uint256 claimTopic
    ) internal view virtual returns (bool) {
        try IERC735(address(userIdentity)).getClaim(keccak256(abi.encode(issuer, claimTopic))) returns (
            uint256 topic,
            uint256,
            address claimIssuer,
            bytes memory signature,
            bytes memory data,
            string memory
        ) {
            if (topic != claimTopic || claimIssuer != address(issuer)) return false;

            // The issuer is asked through a bounded call that only accepts a single word equal to true, so an issuer
            // that reverts or returns oversized data cannot make verification revert.
            (bool success, bytes32 result, ) = LowLevelCall.staticcallReturn64Bytes(
                address(issuer),
                abi.encodeCall(IERC735ClaimIssuer.isClaimValid, (address(userIdentity), claimTopic, signature, data))
            );
            return success && LowLevelCall.returnDataSize() == 32 && uint256(result) == 1;
        } catch {
            return false;
        }
    }
}
