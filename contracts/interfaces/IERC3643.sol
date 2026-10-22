// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

// Subset of `@openzeppelin/contracts/interfaces/IERC3643.sol` needed by the ERC-3643 registries, redeclared
// until https://github.com/OpenZeppelin/openzeppelin-contracts/pull/5838 is released. Keep in sync.

/**
 * @title IIdentityRegistry
 * @dev Interface for the Identity Registry contract in the ERC-3643 ecosystem.
 *
 * The Identity Registry is a crucial component that maintains a dynamic whitelist of verified
 * identities for security token holders. It establishes the link between wallet addresses,
 * Identity smart contracts, and country codes corresponding to investors' countries of residence.
 *
 * Key responsibilities:
 *
 * * Manage investor identity verification and registration
 * * Link wallet addresses to onchain Identity contracts
 * * Store investor country codes (ISO-3166 standard)
 * * Integrate with Trusted Issuers Registry and Claim Topics Registry
 * * Provide verification status for token transfer eligibility
 *
 * The registry works in conjunction with:
 *
 * * Identity Registry Storage: For storing identity data
 * * Trusted Issuers Registry: For managing authorized claim issuers
 * * Claim Topics Registry: For defining required claim topics
 * * Individual Identity contracts: For storing investor claims and credentials
 */
interface IIdentityRegistry {
    /**
     * @dev Emitted when the Claim Topics Registry is set for the Identity Registry.
     *
     * @param claimTopicsRegistry The address of the Claim Topics Registry contract
     */
    event ClaimTopicsRegistrySet(address indexed claimTopicsRegistry);

    /**
     * @dev Emitted when the Identity Registry Storage is set for the Identity Registry.
     *
     * @param identityStorage The address of the Identity Registry Storage contract
     */
    event IdentityStorageSet(address indexed identityStorage);

    /**
     * @dev Emitted when the Trusted Issuers Registry is set for the Identity Registry.
     *
     * @param trustedIssuersRegistry The address of the Trusted Issuers Registry contract
     */
    event TrustedIssuersRegistrySet(address indexed trustedIssuersRegistry);

    /**
     * @dev Emitted when a new investor identity is registered.
     *
     * @param investorAddress The wallet address of the investor
     * @param identity The address of the investor's Identity contract
     */
    event IdentityRegistered(address indexed investorAddress, IIdentity indexed identity);

    /**
     * @dev Emitted when an investor identity is removed from the registry.
     *
     * @param investorAddress The wallet address of the investor
     * @param identity The address of the investor's Identity contract that was removed
     */
    event IdentityRemoved(address indexed investorAddress, IIdentity indexed identity);

    /**
     * @dev Emitted when an investor's identity contract is updated.
     *
     * @param oldIdentity The address of the previous Identity contract
     * @param newIdentity The address of the new Identity contract
     */
    event IdentityUpdated(IIdentity indexed oldIdentity, IIdentity indexed newIdentity);

    /**
     * @dev Emitted when an investor's country code is updated.
     *
     * @param investorAddress The wallet address of the investor
     * @param country The new country code (ISO-3166 standard)
     */
    event CountryUpdated(address indexed investorAddress, uint16 indexed country);

    /**
     * @dev Returns the Identity Registry Storage contract.
     *
     * @return The Identity Registry Storage contract interface
     */
    function identityStorage() external view returns (IIdentityRegistryStorage);

    /**
     * @dev Returns the Trusted Issuers Registry contract.
     *
     * @return The Trusted Issuers Registry contract interface
     */
    function issuersRegistry() external view returns (ITrustedIssuersRegistry);

    /**
     * @dev Returns the Claim Topics Registry contract.
     *
     * @return The Claim Topics Registry contract interface
     */
    function topicsRegistry() external view returns (IClaimTopicsRegistry);

    /**
     * @dev Sets the Identity Registry Storage contract address.
     *
     * @param _identityRegistryStorage The address of the new Identity Registry Storage contract
     *
     * Requirements:
     *
     * * Only the owner can call this function
     * * `_identityRegistryStorage` must be a valid contract address
     *
     * Emits an {IdentityStorageSet} event.
     */
    function setIdentityRegistryStorage(address _identityRegistryStorage) external;

    /**
     * @dev Sets the Claim Topics Registry contract address.
     *
     * @param _claimTopicsRegistry The address of the new Claim Topics Registry contract
     *
     * Requirements:
     *
     * * Only the owner can call this function
     * * `_claimTopicsRegistry` must be a valid contract address
     *
     * Emits a {ClaimTopicsRegistrySet} event.
     */
    function setClaimTopicsRegistry(address _claimTopicsRegistry) external;

    /**
     * @dev Sets the Trusted Issuers Registry contract address.
     *
     * @param _trustedIssuersRegistry The address of the new Trusted Issuers Registry contract
     *
     * Requirements:
     *
     * * Only the owner can call this function
     * * `_trustedIssuersRegistry` must be a valid contract address
     *
     * Emits a {TrustedIssuersRegistrySet} event.
     */
    function setTrustedIssuersRegistry(address _trustedIssuersRegistry) external;

    /**
     * @dev Registers a new investor identity in the registry.
     *
     * @param _userAddress The wallet address of the investor
     * @param _identity The address of the investor's Identity contract
     * @param _country The country code of the investor (ISO-3166 standard)
     *
     * Requirements:
     *
     * * Only authorized agents can call this function
     * * `_userAddress` must not already be registered
     * * `_identity` must be a valid Identity contract
     * * `_country` must be a valid ISO-3166 country code
     *
     * Emits an {IdentityRegistered} event.
     */
    function registerIdentity(address _userAddress, IIdentity _identity, uint16 _country) external;

    /**
     * @dev Removes an investor identity from the registry.
     *
     * @param _userAddress The wallet address of the investor to remove
     *
     * Requirements:
     *
     * * Only authorized agents can call this function
     * * `_userAddress` must be currently registered
     *
     * Emits an {IdentityRemoved} event.
     */
    function deleteIdentity(address _userAddress) external;

    /**
     * @dev Updates the country code for a registered investor.
     *
     * @param _userAddress The wallet address of the investor
     * @param _country The new country code (ISO-3166 standard)
     *
     * Requirements:
     *
     * * Only authorized agents can call this function
     * * `_userAddress` must be currently registered
     * * `_country` must be a valid ISO-3166 country code
     *
     * Emits a {CountryUpdated} event.
     */
    function updateCountry(address _userAddress, uint16 _country) external;

    /**
     * @dev Updates the Identity contract for a registered investor.
     *
     * @param _userAddress The wallet address of the investor
     * @param _identity The address of the new Identity contract
     *
     * Requirements:
     *
     * * Only authorized agents can call this function
     * * `_userAddress` must be currently registered
     * * `_identity` must be a valid Identity contract
     *
     * Emits an {IdentityUpdated} event.
     */
    function updateIdentity(address _userAddress, IIdentity _identity) external;

    /**
     * @dev Registers multiple investor identities in a single transaction.
     *
     * @param _userAddresses Array of wallet addresses of the investors
     * @param _identities Array of Identity contract addresses
     * @param _countries Array of country codes (ISO-3166 standard)
     *
     * Requirements:
     *
     * * Only authorized agents can call this function
     * * All arrays must have the same length
     * * No `_userAddresses` should already be registered
     * * All `_identities` must be valid Identity contracts
     * * All `_countries` must be valid ISO-3166 country codes
     *
     * Emits multiple {IdentityRegistered} events.
     */
    function batchRegisterIdentity(
        address[] calldata _userAddresses,
        IIdentity[] calldata _identities,
        uint16[] calldata _countries
    ) external;

    /**
     * @dev Checks if a wallet address is registered in the identity registry.
     *
     * @param _userAddress The wallet address to check
     * @return True if the address is registered, false otherwise
     */
    function contains(address _userAddress) external view returns (bool);

    /**
     * @dev Checks if a wallet address is verified and eligible for token operations.
     *
     * This function performs comprehensive verification including:
     *
     * * Address is registered in the identity registry
     * * Associated Identity contract contains required claims
     * * Claims are signed by trusted issuers
     * * All claim topics required by the registry are present
     *
     * @param _userAddress The wallet address to verify
     * @return True if the address is fully verified and eligible, false otherwise
     */
    function isVerified(address _userAddress) external view returns (bool);

    /**
     * @dev Returns the Identity contract associated with a wallet address.
     *
     * @param _userAddress The wallet address to query
     * @return The Identity contract interface, or zero address if not registered
     */
    function identity(address _userAddress) external view returns (IIdentity);

    /**
     * @dev Returns the country code for a registered investor.
     *
     * @param _userAddress The wallet address to query
     * @return The country code (ISO-3166 standard), or 0 if not registered
     */
    function investorCountry(address _userAddress) external view returns (uint16);
}

/**
 * @title IIdentityRegistryStorage
 * @dev Interface for the Identity Registry Storage contract in the ERC-3643 ecosystem.
 *
 * The Identity Registry Storage is a specialized storage contract that maintains the identity
 * addresses of all authorized investors for security tokens linked to the storage contract.
 * It serves as a shared storage layer that can be bound to one or several Identity Registry
 * contracts, enabling efficient data sharing and separation of concerns.
 *
 * Key responsibilities:
 *
 * * Store identity addresses for authorized investors
 * * Maintain investor country codes (ISO-3166 standard)
 * * Manage binding relationships with Identity Registry contracts
 * * Provide shared storage for multiple token ecosystems
 * * Enable separation of registry logic from storage implementation
 *
 * Architecture benefits:
 *
 * * Shared Whitelist: Multiple tokens can use the same investor whitelist
 * * Modular Design: Registry logic separated from storage implementation
 * * Scalability: One storage contract can serve multiple registries
 * * Upgradability: Registry contracts can be updated while preserving data
 * * Access Control: Only bound registries can modify stored data
 */
interface IIdentityRegistryStorage {
    /**
     * @dev Emitted when an investor identity is stored in the storage contract.
     *
     * @param investorAddress The wallet address of the investor
     * @param identity The address of the investor's Identity contract
     */
    event IdentityStored(address indexed investorAddress, IIdentity indexed identity);

    /**
     * @dev Emitted when an investor identity is removed from the storage contract.
     *
     * @param investorAddress The wallet address of the investor
     * @param identity The address of the investor's Identity contract that was removed
     */
    event IdentityUnstored(address indexed investorAddress, IIdentity indexed identity);

    /**
     * @dev Emitted when an investor's identity contract is modified in storage.
     *
     * @param oldIdentity The address of the previous Identity contract
     * @param newIdentity The address of the new Identity contract
     */
    event IdentityModified(IIdentity indexed oldIdentity, IIdentity indexed newIdentity);

    /**
     * @dev Emitted when an investor's country code is modified in storage.
     *
     * @param investorAddress The wallet address of the investor
     * @param country The new country code (ISO-3166 standard)
     */
    event CountryModified(address indexed investorAddress, uint16 indexed country);

    /**
     * @dev Emitted when an Identity Registry contract is bound to this storage.
     *
     * @param identityRegistry The address of the Identity Registry contract that was bound
     */
    event IdentityRegistryBound(address indexed identityRegistry);

    /**
     * @dev Emitted when an Identity Registry contract is unbound from this storage.
     *
     * @param identityRegistry The address of the Identity Registry contract that was unbound
     */
    event IdentityRegistryUnbound(address indexed identityRegistry);

    /**
     * @dev Returns the Identity contract stored for a given wallet address.
     *
     * @param _userAddress The wallet address to query
     * @return The Identity contract interface, or zero address if not stored
     */
    function storedIdentity(address _userAddress) external view returns (IIdentity);

    /**
     * @dev Returns the country code stored for a given investor.
     *
     * @param _userAddress The wallet address to query
     * @return The country code (ISO-3166 standard), or 0 if not stored
     */
    function storedInvestorCountry(address _userAddress) external view returns (uint16);

    /**
     * @dev Adds an investor identity to storage.
     *
     * @param _userAddress The wallet address of the investor
     * @param _identity The address of the investor's Identity contract
     * @param _country The country code of the investor (ISO-3166 standard)
     *
     * Requirements:
     *
     * * Only bound Identity Registry contracts can call this function
     * * `_userAddress` must not already be stored
     * * `_identity` must be a valid Identity contract address
     * * `_country` must be a valid ISO-3166 country code
     *
     * Emits an {IdentityStored} event.
     */
    function addIdentityToStorage(address _userAddress, IIdentity _identity, uint16 _country) external;

    /**
     * @dev Removes an investor identity from storage.
     *
     * @param _userAddress The wallet address of the investor to remove
     *
     * Requirements:
     *
     * * Only bound Identity Registry contracts can call this function
     * * `_userAddress` must be currently stored
     *
     * Emits an {IdentityUnstored} event.
     */
    function removeIdentityFromStorage(address _userAddress) external;

    /**
     * @dev Modifies the country code for a stored investor.
     *
     * @param _userAddress The wallet address of the investor
     * @param _country The new country code (ISO-3166 standard)
     *
     * Requirements:
     *
     * * Only bound Identity Registry contracts can call this function
     * * `_userAddress` must be currently stored
     * * `_country` must be a valid ISO-3166 country code
     *
     * Emits a {CountryModified} event.
     */
    function modifyStoredInvestorCountry(address _userAddress, uint16 _country) external;

    /**
     * @dev Modifies the Identity contract for a stored investor.
     *
     * @param _userAddress The wallet address of the investor
     * @param _identity The address of the new Identity contract
     *
     * Requirements:
     *
     * * Only bound Identity Registry contracts can call this function
     * * `_userAddress` must be currently stored
     * * `_identity` must be a valid Identity contract address
     *
     * Emits an {IdentityModified} event.
     */
    function modifyStoredIdentity(address _userAddress, IIdentity _identity) external;

    /**
     * @dev Binds an Identity Registry contract to this storage, granting it write access.
     *
     * @param _identityRegistry The address of the Identity Registry contract to bind
     *
     * Requirements:
     *
     * * Only the owner can call this function
     * * `_identityRegistry` must be a valid contract address
     * * `_identityRegistry` must not already be bound
     *
     * Emits an {IdentityRegistryBound} event.
     */
    function bindIdentityRegistry(address _identityRegistry) external;

    /**
     * @dev Unbinds an Identity Registry contract from this storage, revoking its write access.
     *
     * @param _identityRegistry The address of the Identity Registry contract to unbind
     *
     * Requirements:
     *
     * * Only the owner can call this function
     * * `_identityRegistry` must be currently bound
     *
     * Emits an {IdentityRegistryUnbound} event.
     */
    function unbindIdentityRegistry(address _identityRegistry) external;

    /**
     * @dev Returns an array of all Identity Registry contracts bound to this storage.
     *
     * @return Array of addresses of bound Identity Registry contracts
     */
    function linkedIdentityRegistries() external view returns (address[] memory);
}

/**
 * @title ITrustedIssuersRegistry
 * @dev Interface for the Trusted Issuers Registry contract in the ERC-3643 ecosystem.
 *
 * The Trusted Issuers Registry manages a whitelist of authorized claim issuers that are
 * trusted to provide valid claims for identity verification. It defines which claim issuers
 * are authorized and what types of claims (topics) each issuer is allowed to emit.
 *
 * Key responsibilities:
 *
 * * Maintain a registry of trusted claim issuer contracts
 * * Define claim topics that each issuer is authorized to emit
 * * Provide validation for claim issuer authorization
 * * Enable efficient lookup of issuers by claim topic
 *
 * Claim topics are numeric identifiers representing different types of claims:
 *
 * * Example: KYC = 1, AML = 2, Accreditation = 3, etc.
 *
 * The registry works in conjunction with:
 *
 * * Identity Registry: For identity verification processes
 * * Identity contracts: For claim validation
 * * Compliance contracts: For regulatory requirement enforcement
 * * Claim Topics Registry: For defining required claim types
 */
interface ITrustedIssuersRegistry {
    /**
     * @dev Emitted when a trusted issuer is added to the registry.
     *
     * @param trustedIssuer The address of the claim issuer contract that was added
     * @param claimTopics Array of claim topic IDs that the issuer is authorized to emit
     */
    event TrustedIssuerAdded(IClaimIssuer indexed trustedIssuer, uint256[] claimTopics);

    /**
     * @dev Emitted when a trusted issuer is removed from the registry.
     *
     * @param trustedIssuer The address of the claim issuer contract that was removed
     */
    event TrustedIssuerRemoved(IClaimIssuer indexed trustedIssuer);

    /**
     * @dev Emitted when the authorized claim topics for a trusted issuer are updated.
     *
     * @param trustedIssuer The address of the claim issuer contract that was updated
     * @param claimTopics Array of new claim topic IDs that the issuer is authorized to emit
     */
    event ClaimTopicsUpdated(IClaimIssuer indexed trustedIssuer, uint256[] claimTopics);

    /**
     * @dev Adds a claim issuer to the trusted registry with authorized claim topics.
     *
     * @param _trustedIssuer The address of the claim issuer contract to add
     * @param _claimTopics Array of claim topic IDs that the issuer is authorized to emit
     *
     * Requirements:
     *
     * * Only the owner can call this function
     * * `_trustedIssuer` must be a valid claim issuer contract
     * * `_trustedIssuer` must not already be registered
     * * `_claimTopics` array must not be empty
     * * `_claimTopics` array must not exceed 15 topics (gas optimization)
     * * Registry must not exceed 50 trusted issuers (gas optimization)
     *
     * Emits a {TrustedIssuerAdded} event.
     */
    function addTrustedIssuer(IClaimIssuer _trustedIssuer, uint256[] calldata _claimTopics) external;

    /**
     * @dev Removes a claim issuer from the trusted registry.
     *
     * @param _trustedIssuer The address of the claim issuer contract to remove
     *
     * Requirements:
     *
     * * Only the owner can call this function
     * * `_trustedIssuer` must be currently registered as a trusted issuer
     *
     * Emits a {TrustedIssuerRemoved} event.
     */
    function removeTrustedIssuer(IClaimIssuer _trustedIssuer) external;

    /**
     * @dev Updates the authorized claim topics for an existing trusted issuer.
     *
     * @param _trustedIssuer The address of the claim issuer contract to update
     * @param _claimTopics Array of new claim topic IDs that the issuer is authorized to emit
     *
     * Requirements:
     *
     * * Only the owner can call this function
     * * `_trustedIssuer` must be currently registered as a trusted issuer
     * * `_claimTopics` array must not be empty
     * * `_claimTopics` array must not exceed 15 topics (gas optimization)
     *
     * Emits a {ClaimTopicsUpdated} event.
     */
    function updateIssuerClaimTopics(IClaimIssuer _trustedIssuer, uint256[] calldata _claimTopics) external;

    /**
     * @dev Returns an array of all registered trusted claim issuers.
     *
     * @return Array of trusted claim issuer contract addresses
     */
    function getTrustedIssuers() external view returns (IClaimIssuer[] memory);

    /**
     * @dev Checks if a given address is registered as a trusted claim issuer.
     *
     * @param _issuer The address to check
     * @return True if the address is a registered trusted issuer, false otherwise
     */
    function isTrustedIssuer(address _issuer) external view returns (bool);

    /**
     * @dev Returns the claim topics that a trusted issuer is authorized to emit.
     *
     * @param _trustedIssuer The address of the trusted claim issuer
     * @return Array of claim topic IDs that the issuer is authorized to emit
     *
     * Requirements:
     *
     * * `_trustedIssuer` must be registered as a trusted issuer
     */
    function getTrustedIssuerClaimTopics(IClaimIssuer _trustedIssuer) external view returns (uint256[] memory);

    /**
     * @dev Returns all trusted issuers that are authorized to emit a specific claim topic.
     * @param claimTopic The claim topic ID to query
     * @return Array of trusted claim issuer addresses authorized for the given topic
     */
    function getTrustedIssuersForClaimTopic(uint256 claimTopic) external view returns (IClaimIssuer[] memory);

    /**
     * @dev Checks if a trusted issuer is authorized to emit a specific claim topic.
     *
     * @param _issuer The address of the claim issuer to check
     * @param _claimTopic The claim topic ID to check authorization for
     * @return True if the issuer is authorized for the claim topic, false otherwise
     */
    function hasClaimTopic(address _issuer, uint256 _claimTopic) external view returns (bool);
}

/**
 * @title IClaimTopicsRegistry
 * @dev Interface for the Claim Topics Registry contract in the ERC-3643 ecosystem.
 *
 * The Claim Topics Registry defines the types of claims that are required for identity
 * verification in the security token ecosystem. It maintains a registry of trusted claim
 * topics that investors must possess to be eligible for token operations.
 *
 * Key responsibilities:
 *
 * * Define required claim topic IDs for token eligibility
 * * Manage the list of accepted claim types
 * * Provide claim topic validation for identity verification
 * * Enable flexible claim requirement configuration
 *
 * Claim topics are numeric identifiers representing different verification requirements:
 *
 * * Example: KYC = 1, AML = 2, Accreditation = 3, Residency = 4, etc.
 *
 * Architecture considerations:
 *
 * * Maximum 15 topics per token (gas optimization)
 * * Topics are defined at the token ecosystem level
 * * Claims must be issued by trusted issuers for these topics
 * * Claims are validated during identity verification processes
 *
 * The registry works in conjunction with:
 *
 * * Identity Registry: For comprehensive identity verification
 * * Trusted Issuers Registry: For validating claim issuers
 * * Identity contracts: For storing and retrieving claims
 * * Compliance contracts: For enforcing claim requirements
 */
interface IClaimTopicsRegistry {
    /**
     * @dev Emitted when a claim topic is added to the registry.
     *
     * @param claimTopic The numeric ID of the claim topic that was added
     */
    event ClaimTopicAdded(uint256 indexed claimTopic);

    /**
     * @dev Emitted when a claim topic is removed from the registry.
     *
     * @param claimTopic The numeric ID of the claim topic that was removed
     */
    event ClaimTopicRemoved(uint256 indexed claimTopic);

    /**
     * @dev Adds a new claim topic to the registry.
     *
     * Claim topics represent different types of verification requirements
     * that investors must meet. Each topic corresponds to a specific type
     * of claim that must be present in an investor's identity contract.
     *
     * @param _claimTopic The numeric identifier for the claim topic
     *
     * Requirements:
     *
     * * Only the owner can call this function
     * * `_claimTopic` must not already be registered
     * * Registry must not exceed 15 topics (gas optimization)
     * * `_claimTopic` must not be zero
     *
     * Emits a {ClaimTopicAdded} event.
     */
    function addClaimTopic(uint256 _claimTopic) external;

    /**
     * @dev Removes a claim topic from the registry.
     *
     * After removal, claims of this topic will no longer be required
     * for identity verification in this token ecosystem.
     *
     * @param _claimTopic The numeric identifier for the claim topic to remove
     *
     * Requirements:
     *
     * * Only the owner can call this function
     * * `_claimTopic` must be currently registered
     *
     * Emits a {ClaimTopicRemoved} event.
     */
    function removeClaimTopic(uint256 _claimTopic) external;

    /**
     * @dev Returns all registered claim topics for this token ecosystem.
     *
     * This function provides the complete list of claim types that investors
     * must possess to be eligible for token operations.
     *
     * @return Array of claim topic IDs currently registered
     */
    function getClaimTopics() external view returns (uint256[] memory);
}

/**
 * @title IIdentity
 * @dev Minimal interface representing an identity contract address.
 *
 * This interface serves as a type-safe wrapper for identity contract addresses
 * in the ERC-3643 ecosystem. The actual identity functionality is implementation-
 * specific and not defined by ERC-3643.
 *
 * Implementers are free to use any identity system that provides:
 *
 * * Onchain identity verification
 * * Claim management capabilities
 * * Integration with trusted claim issuers
 *
 * NOTE: Not formally defined in ERC-3643. Provided for convenience.
 */
interface IIdentity {
    enum KeyPurpose {
        Management,
        Execution
    }

    /**
     * @dev Checks if a key has a specific purpose.
     */
    function keyHasPurpose(bytes32 key, KeyPurpose purpose) external view returns (bool);
}

/**
 * @title IClaimIssuer
 * @dev Minimal interface representing a claim issuer contract address.
 *
 * This interface serves as a type-safe wrapper for claim issuer contract addresses.
 * Claim issuers are trusted entities that can issue verifiable claims about identities.
 */
// Empty interface serves as a type marker for claim issuer contracts since it's not defined by ERC-3643
interface IClaimIssuer {}
