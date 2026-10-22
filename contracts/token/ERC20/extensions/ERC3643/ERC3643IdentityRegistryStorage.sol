// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IIdentity, IIdentityRegistryStorage} from "../../../../interfaces/IERC3643.sol";

/**
 * @dev Implementation of the ERC-3643 Identity Registry Storage: the identity contract and country of each
 * wallet, shared by every {ERC3643IdentityRegistry} bound to it.
 *
 * As the standard requires, only bound identity registries can write identities. Binding and unbinding
 * registries is restricted by {_authorizeRegistryBinding}, which derived contracts implement:
 *
 * ```solidity
 * contract MyIdentityRegistryStorage is ERC3643IdentityRegistryStorage, Ownable {
 *     constructor(address initialOwner) Ownable(initialOwner) {}
 *
 *     function _authorizeRegistryBinding() internal view override onlyOwner {}
 * }
 * ```
 *
 * A wallet is stored while it has a non-zero identity contract. Its country is kept alongside and cleared when
 * the wallet is removed.
 */
abstract contract ERC3643IdentityRegistryStorage is Context, IIdentityRegistryStorage {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct StoredIdentity {
        IIdentity identity;
        uint16 country;
    }

    mapping(address account => StoredIdentity) private _identities;
    EnumerableSet.AddressSet private _identityRegistries;

    /// @dev The wallet is not a valid address.
    error ERC3643InvalidAccount(address account);

    /// @dev The identity contract is not a valid address.
    error ERC3643InvalidIdentity(IIdentity identity);

    /// @dev The wallet already has a stored identity.
    error ERC3643IdentityAlreadyStored(address account);

    /// @dev The wallet has no stored identity.
    error ERC3643IdentityNotStored(address account);

    /// @dev The identity registry is not a valid address.
    error ERC3643InvalidIdentityRegistry(address identityRegistry);

    /// @dev The identity registry is already bound.
    error ERC3643IdentityRegistryAlreadyBound(address identityRegistry);

    /// @dev The identity registry is not bound.
    error ERC3643IdentityRegistryNotBound(address identityRegistry);

    /// @dev The caller is not a bound identity registry.
    error ERC3643UnauthorizedIdentityRegistry(address caller);

    /// @inheritdoc IIdentityRegistryStorage
    function storedIdentity(address account) public view virtual returns (IIdentity) {
        return _identities[account].identity;
    }

    /// @inheritdoc IIdentityRegistryStorage
    function storedInvestorCountry(address account) public view virtual returns (uint16) {
        return _identities[account].country;
    }

    /// @inheritdoc IIdentityRegistryStorage
    function linkedIdentityRegistries() public view virtual returns (address[] memory) {
        return _identityRegistries.values();
    }

    /// @inheritdoc IIdentityRegistryStorage
    function addIdentityToStorage(address account, IIdentity identity, uint16 country) public virtual {
        _authorizeIdentityWrite();
        require(_addIdentityToStorage(account, identity, country), ERC3643IdentityAlreadyStored(account));
    }

    /// @inheritdoc IIdentityRegistryStorage
    function removeIdentityFromStorage(address account) public virtual {
        _authorizeIdentityWrite();
        require(_removeIdentityFromStorage(account), ERC3643IdentityNotStored(account));
    }

    /// @inheritdoc IIdentityRegistryStorage
    function modifyStoredInvestorCountry(address account, uint16 country) public virtual {
        _authorizeIdentityWrite();
        require(_modifyStoredInvestorCountry(account, country), ERC3643IdentityNotStored(account));
    }

    /// @inheritdoc IIdentityRegistryStorage
    function modifyStoredIdentity(address account, IIdentity identity) public virtual {
        _authorizeIdentityWrite();
        require(_modifyStoredIdentity(account, identity), ERC3643IdentityNotStored(account));
    }

    /// @inheritdoc IIdentityRegistryStorage
    function bindIdentityRegistry(address identityRegistry) public virtual {
        _authorizeRegistryBinding();
        require(_bindIdentityRegistry(identityRegistry), ERC3643IdentityRegistryAlreadyBound(identityRegistry));
    }

    /// @inheritdoc IIdentityRegistryStorage
    function unbindIdentityRegistry(address identityRegistry) public virtual {
        _authorizeRegistryBinding();
        require(_unbindIdentityRegistry(identityRegistry), ERC3643IdentityRegistryNotBound(identityRegistry));
    }

    /**
     * @dev Reverts if the caller is not allowed to write identities. By default, only bound identity registries
     * are.
     */
    function _authorizeIdentityWrite() internal virtual {
        address caller = _msgSender();
        require(_identityRegistries.contains(caller), ERC3643UnauthorizedIdentityRegistry(caller));
    }

    /// @dev Reverts if the caller is not allowed to bind or unbind identity registries.
    function _authorizeRegistryBinding() internal virtual;

    /**
     * @dev Stores `identity` and `country` for `account`. Returns false if `account` already has a stored identity.
     *
     * Requirements:
     *
     * * `account` must not be the zero address.
     * * `identity` must not be the zero address.
     *
     * Emits an {IdentityStored} event when the identity is stored.
     */
    function _addIdentityToStorage(
        address account,
        IIdentity identity,
        uint16 country
    ) internal virtual returns (bool) {
        require(account != address(0), ERC3643InvalidAccount(address(0)));
        require(address(identity) != address(0), ERC3643InvalidIdentity(identity));
        StoredIdentity storage stored = _identities[account];
        if (address(stored.identity) != address(0)) return false;
        stored.identity = identity;
        stored.country = country;
        emit IdentityStored(account, identity);
        return true;
    }

    /**
     * @dev Removes the identity and country stored for `account`. Returns false if it has no stored identity.
     *
     * Emits an {IdentityUnstored} event when the identity is removed.
     */
    function _removeIdentityFromStorage(address account) internal virtual returns (bool) {
        IIdentity identity = _identities[account].identity;
        if (address(identity) == address(0)) return false;
        delete _identities[account];
        emit IdentityUnstored(account, identity);
        return true;
    }

    /**
     * @dev Replaces the country stored for `account`. Returns false if it has no stored identity.
     *
     * Emits a {CountryModified} event when the country is replaced.
     */
    function _modifyStoredInvestorCountry(address account, uint16 country) internal virtual returns (bool) {
        StoredIdentity storage stored = _identities[account];
        if (address(stored.identity) == address(0)) return false;
        stored.country = country;
        emit CountryModified(account, country);
        return true;
    }

    /**
     * @dev Replaces the identity contract stored for `account`. Returns false if it has no stored identity.
     *
     * Requirements:
     *
     * * `identity` must not be the zero address. Use {_removeIdentityFromStorage} to remove a wallet.
     *
     * Emits an {IdentityModified} event when the identity is replaced.
     */
    function _modifyStoredIdentity(address account, IIdentity identity) internal virtual returns (bool) {
        require(address(identity) != address(0), ERC3643InvalidIdentity(identity));
        StoredIdentity storage stored = _identities[account];
        IIdentity oldIdentity = stored.identity;
        if (address(oldIdentity) == address(0)) return false;
        stored.identity = identity;
        emit IdentityModified(oldIdentity, identity);
        return true;
    }

    /**
     * @dev Allows `identityRegistry` to write identities. Returns false if it was already bound.
     *
     * Requirements:
     *
     * * `identityRegistry` must not be the zero address.
     *
     * Emits an {IdentityRegistryBound} event when the registry is bound.
     */
    function _bindIdentityRegistry(address identityRegistry) internal virtual returns (bool) {
        require(identityRegistry != address(0), ERC3643InvalidIdentityRegistry(address(0)));
        if (!_identityRegistries.add(identityRegistry)) return false;
        emit IdentityRegistryBound(identityRegistry);
        return true;
    }

    /**
     * @dev Stops allowing `identityRegistry` to write identities. Returns false if it was not bound.
     *
     * Emits an {IdentityRegistryUnbound} event when the registry is unbound.
     */
    function _unbindIdentityRegistry(address identityRegistry) internal virtual returns (bool) {
        if (!_identityRegistries.remove(identityRegistry)) return false;
        emit IdentityRegistryUnbound(identityRegistry);
        return true;
    }
}
