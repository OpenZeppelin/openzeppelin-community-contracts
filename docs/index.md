# Solidity API

## AccessManagerLight

_Light version of an AccessManager contract that defines `bytes8` roles
that are stored as requirements (see {getRequirements}) for each function.

Each requirement is a bitmask of roles that are allowed to call a function
identified by its `bytes4` selector. Users have their permissioned stored
as a bitmask of roles they belong to.

The admin role is a special role that has access to all functions and can
manage the roles of other users._

### ADMIN_ROLE

```solidity
uint8 ADMIN_ROLE
```

### PUBLIC_ROLE

```solidity
uint8 PUBLIC_ROLE
```

### ADMIN_MASK

```solidity
Masks.Mask ADMIN_MASK
```

### PUBLIC_MASK

```solidity
Masks.Mask PUBLIC_MASK
```

### GroupAdded

```solidity
event GroupAdded(address user, uint8 group)
```

### GroupRemoved

```solidity
event GroupRemoved(address user, uint8 group)
```

### GroupAdmins

```solidity
event GroupAdmins(uint8 group, Masks.Mask admins)
```

### RequirementsSet

```solidity
event RequirementsSet(address target, bytes4 selector, Masks.Mask groups)
```

### MissingPermissions

```solidity
error MissingPermissions(address user, Masks.Mask permissions, Masks.Mask requirement)
```

### onlyRole

```solidity
modifier onlyRole(Masks.Mask requirement)
```

_Throws if the specified requirement is not met by the caller's permissions (see {getGroups})._

### constructor

```solidity
constructor(address admin) public
```

_Initializes the contract with the `admin` as the first member of the admin group._

### canCall

```solidity
function canCall(address caller, address target, bytes4 selector) public view returns (bool)
```

_Returns whether the `caller` has the required permissions to call the `target` with the `selector`._

### getGroups

```solidity
function getGroups(address user) public view returns (Masks.Mask)
```

_Returns the groups that the `user` belongs to._

### getGroupAdmins

```solidity
function getGroupAdmins(uint8 group) public view returns (Masks.Mask)
```

_Returns the admins of the `group`._

### getRequirements

```solidity
function getRequirements(address target, bytes4 selector) public view returns (Masks.Mask)
```

_Returns the requirements for the `target` and `selector`._

### addGroup

```solidity
function addGroup(address user, uint8 group) public
```

_Adds the `user` to the `group`. Emits {GroupAdded} event._

### remGroup

```solidity
function remGroup(address user, uint8 group) public
```

_Removes the `user` from the `group`. Emits {GroupRemoved} event._

### _addGroup

```solidity
function _addGroup(address user, uint8 group) internal
```

_Internal version of {addGroup} without access control._

### _remGroup

```solidity
function _remGroup(address user, uint8 group) internal
```

_Internal version of {remGroup} without access control._

### setGroupAdmins

```solidity
function setGroupAdmins(uint8 group, uint8[] admins) public
```

_Sets the `admins` of the `group`. Emits {GroupAdmins} event._

### _setGroupAdmins

```solidity
function _setGroupAdmins(uint8 group, Masks.Mask admins) internal
```

_Internal version of {_setGroupAdmins} without access control._

### setRequirements

```solidity
function setRequirements(address target, bytes4[] selectors, uint8[] groups) public
```

_Sets the `groups` requirements for the `selectors` of the `target`._

### _setRequirements

```solidity
function _setRequirements(address target, bytes4 selector, Masks.Mask groups) internal
```

_Internal version of {_setRequirements} without access control._

## ERC7739SignerMock

### constructor

```solidity
constructor(address eoa) public
```

### _validateSignature

```solidity
function _validateSignature(bytes32 hash, bytes signature) internal view virtual returns (bool)
```

_Signature validation algorithm.

WARNING: Implementing a signature validation algorithm is a security-sensitive operation as it involves
cryptographic verification. It is important to review and test thoroughly before deployment. Consider
using one of the signature verification libraries ({ECDSA}, {P256} or {RSA})._

## MyStablecoinAllowlist

### constructor

```solidity
constructor(address initialAuthority) public
```

### allowUser

```solidity
function allowUser(address user) public
```

### disallowUser

```solidity
function disallowUser(address user) public
```

## ERC20CollateralMock

### constructor

```solidity
constructor(uint48 liveness_, string name_, string symbol_) internal
```

### collateral

```solidity
function collateral() public view returns (uint256 amount, uint48 timestamp)
```

_Returns the collateral data of the token._

## ERC20CustodianMock

### constructor

```solidity
constructor(address custodian, string name_, string symbol_) internal
```

### _isCustodian

```solidity
function _isCustodian(address user) internal view returns (bool)
```

_Checks if the user is a custodian._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | The address of the user to check. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | True if the user is authorized, false otherwise. |

## HybridProxy

_A version of an ERC-1967 proxy that uses the address stored in the implementation slot as a beacon.

The design allows to set an initial beacon that the contract may quit by upgrading to its own implementation
afterwards.

WARNING: The fallback mechanism relies on the implementation not to define the {IBeacon-implementation} function.
Consider that if your implementation has this function, it'll be assumed as the beacon address, meaning that
the returned address will be used as this proxy's implementation._

### constructor

```solidity
constructor(address implementation, bytes data) public
```

_Initializes the proxy with an initial implementation. If data is present, it will be used to initialize the
implementation using a delegate call._

### _implementation

```solidity
function _implementation() internal view returns (address)
```

_Returns the current implementation address according to ERC-1967's implementation slot.

IMPORTANT: The way this function identifies whether the implementation is a beacon, is by checking
if it implements the {IBeacon-implementation} function. Consider that an actual implementation could
define this function, mistakenly identifying it as a beacon._

## ERC20Allowlist

_Extension of {ERC20} that allows to implement an allowlist
mechanism that can be managed by an authorized account with the
{_disallowUser} and {_allowUser} functions.

The allowlist provides the guarantee to the contract owner
(e.g. a DAO or a well-configured multisig) that any account won't be
able to execute transfers or approvals to other entities to operate
on its behalf if {_allowUser} was not called with such account as an
argument. Similarly, the account will be disallowed again if
{_disallowUser} is called._

### _allowed

```solidity
mapping(address => bool) _allowed
```

_Allowed status of addresses. True if allowed, False otherwise._

### UserAllowed

```solidity
event UserAllowed(address user)
```

_Emitted when a `user` is allowed to transfer and approve._

### UserDisallowed

```solidity
event UserDisallowed(address user)
```

_Emitted when a user is disallowed._

### ERC20Disallowed

```solidity
error ERC20Disallowed(address user)
```

_The operation failed because the user is not allowed._

### allowed

```solidity
function allowed(address account) public virtual returns (bool)
```

_Returns the allowed status of an account._

### _allowUser

```solidity
function _allowUser(address user) internal virtual returns (bool)
```

_Allows a user to receive and transfer tokens, including minting and burning._

### _disallowUser

```solidity
function _disallowUser(address user) internal virtual returns (bool)
```

_Disallows a user from receiving and transferring tokens, including minting and burning._

### _update

```solidity
function _update(address from, address to, uint256 value) internal virtual
```

_See {ERC20-_update}._

### _approve

```solidity
function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual
```

_See {ERC20-_approve}._

## ERC20Blocklist

_Extension of {ERC20} that allows to implement a blocklist
mechanism that can be managed by an authorized account with the
{_blockUser} and {_unblockUser} functions.

The blocklist provides the guarantee to the contract owner
(e.g. a DAO or a well-configured multisig) that any account won't be
able to execute transfers or approvals to other entities to operate
on its behalf if {_blockUser} was not called with such account as an
argument. Similarly, the account will be unblocked again if
{_unblockUser} is called._

### _blocked

```solidity
mapping(address => bool) _blocked
```

_Blocked status of addresses. True if blocked, False otherwise._

### UserBlocked

```solidity
event UserBlocked(address user)
```

_Emitted when a user is blocked._

### UserUnblocked

```solidity
event UserUnblocked(address user)
```

_Emitted when a user is unblocked._

### ERC20Blocked

```solidity
error ERC20Blocked(address user)
```

_The operation failed because the user is blocked._

### blocked

```solidity
function blocked(address account) public virtual returns (bool)
```

_Returns the blocked status of an account._

### _blockUser

```solidity
function _blockUser(address user) internal virtual returns (bool)
```

_Blocks a user from receiving and transferring tokens, including minting and burning._

### _unblockUser

```solidity
function _unblockUser(address user) internal virtual returns (bool)
```

_Unblocks a user from receiving and transferring tokens, including minting and burning._

### _update

```solidity
function _update(address from, address to, uint256 value) internal virtual
```

_See {ERC20-_update}._

### _approve

```solidity
function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual
```

_See {ERC20-_approve}._

## ERC20Collateral

_Extension of {ERC20} that limits the supply of tokens based
on a collateral amount and time-based expiration.

The {collateral} function must be implemented to return the collateral
data. This function can call external oracles or use any local storage._

### ERC20ExceededSupply

```solidity
error ERC20ExceededSupply(uint256 increasedSupply, uint256 cap)
```

_Total supply cap has been exceeded._

### ERC20ExpiredCollateral

```solidity
error ERC20ExpiredCollateral(uint48 timestamp, uint48 expiration)
```

_Collateral amount has expired._

### constructor

```solidity
constructor(uint48 liveness_) internal
```

_Sets the value of the `_liveness`. This value is immutable, it can only be
set once during construction._

### liveness

```solidity
function liveness() public view virtual returns (uint48)
```

_Returns the minimum liveness duration of collateral._

### clock

```solidity
function clock() public view virtual returns (uint48)
```

_Clock used for flagging checkpoints. Can be overridden to implement timestamp based checkpoints (and voting)._

### CLOCK_MODE

```solidity
function CLOCK_MODE() public view virtual returns (string)
```

_Description of the clock_

### collateral

```solidity
function collateral() public view virtual returns (uint256 amount, uint48 timestamp)
```

_Returns the collateral data of the token._

### _update

```solidity
function _update(address from, address to, uint256 value) internal virtual
```

_See {ERC20-_update}._

## ERC20Custodian

_Extension of {ERC20} that allows to implement a custodian
mechanism that can be managed by an authorized account with the
{freeze} and {unfreeze} functions.

This mechanism allows a custodian (e.g. a DAO or a
well-configured multisig) to freeze and unfreeze the balance
of a user.

The frozen balance is not available for transfers or approvals
to other entities to operate on its behalf if {freeze} was not
called with such account as an argument. Similarly, the account
will be unfrozen again if {unfreeze} is called._

### _frozen

```solidity
mapping(address => uint256) _frozen
```

_The amount of tokens frozen by user address._

### TokensFrozen

```solidity
event TokensFrozen(address user, uint256 amount)
```

_Emitted when tokens are frozen for a user._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | The address of the user whose tokens were frozen. |
| amount | uint256 | The amount of tokens that were frozen. |

### TokensUnfrozen

```solidity
event TokensUnfrozen(address user, uint256 amount)
```

_Emitted when tokens are unfrozen for a user._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | The address of the user whose tokens were unfrozen. |
| amount | uint256 | The amount of tokens that were unfrozen. |

### ERC20InsufficientUnfrozenBalance

```solidity
error ERC20InsufficientUnfrozenBalance(address user)
```

_The operation failed because the user has insufficient unfrozen balance._

### ERC20InsufficientFrozenBalance

```solidity
error ERC20InsufficientFrozenBalance(address user)
```

_The operation failed because the user has insufficient frozen balance._

### ERC20NotCustodian

```solidity
error ERC20NotCustodian()
```

_Error thrown when a non-custodian account attempts to perform a custodian-only operation._

### onlyCustodian

```solidity
modifier onlyCustodian()
```

_Modifier to restrict access to custodian accounts only._

### frozen

```solidity
function frozen(address user) public view virtual returns (uint256)
```

_Returns the amount of tokens frozen for a user._

### freeze

```solidity
function freeze(address user, uint256 amount) external virtual
```

_Adjusts the amount of tokens frozen for a user._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | The address of the user whose tokens to freeze. |
| amount | uint256 | The amount of tokens frozen. Requirements: - The user must have sufficient unfrozen balance. |

### availableBalance

```solidity
function availableBalance(address account) public view returns (uint256 available)
```

_Returns the available (unfrozen) balance of an account._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| account | address | The address to query the available balance of. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| available | uint256 | The amount of tokens available for transfer. |

### _isCustodian

```solidity
function _isCustodian(address user) internal view virtual returns (bool)
```

_Checks if the user is a custodian._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| user | address | The address of the user to check. |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | bool | True if the user is authorized, false otherwise. |

### _update

```solidity
function _update(address from, address to, uint256 value) internal virtual
```

_Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
(or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
this function.

Emits a {Transfer} event._

## ERC4626Fees

_ERC-4626 vault with entry/exit fees expressed in https://en.wikipedia.org/wiki/Basis_point[basis point (bp)]._

### previewDeposit

```solidity
function previewDeposit(uint256 assets) public view virtual returns (uint256)
```

_Preview taking an entry fee on deposit. See {IERC4626-previewDeposit}._

### previewMint

```solidity
function previewMint(uint256 shares) public view virtual returns (uint256)
```

_Preview adding an entry fee on mint. See {IERC4626-previewMint}._

### previewWithdraw

```solidity
function previewWithdraw(uint256 assets) public view virtual returns (uint256)
```

_Preview adding an exit fee on withdraw. See {IERC4626-previewWithdraw}._

### previewRedeem

```solidity
function previewRedeem(uint256 shares) public view virtual returns (uint256)
```

_Preview taking an exit fee on redeem. See {IERC4626-previewRedeem}._

### _deposit

```solidity
function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal virtual
```

_Send entry fee to {_entryFeeRecipient}. See {IERC4626-_deposit}._

### _withdraw

```solidity
function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal virtual
```

_Send exit fee to {_exitFeeRecipient}. See {IERC4626-_deposit}._

### _entryFeeBasisPoints

```solidity
function _entryFeeBasisPoints() internal view virtual returns (uint256)
```

### _exitFeeBasisPoints

```solidity
function _exitFeeBasisPoints() internal view virtual returns (uint256)
```

### _entryFeeRecipient

```solidity
function _entryFeeRecipient() internal view virtual returns (address)
```

### _exitFeeRecipient

```solidity
function _exitFeeRecipient() internal view virtual returns (address)
```

## OnTokenTransferAdapter

_This contract exposes the 667 `onTokenTransfer` hook on top of {IERC1363Receiver-onTransferReceived}.

Inheriting from this adapter makes your `ERC1363Receiver` contract automatically compatible with tokens, such as
Chainlink's Link, that implement the 667 interface for transferAndCall._

### onTokenTransfer

```solidity
function onTokenTransfer(address from, uint256 amount, bytes data) public virtual returns (bool)
```

## Masks

_Library for handling bit masks_

### Mask

### toMask

```solidity
function toMask(uint8 group) internal pure returns (Masks.Mask)
```

_Returns a new mask with the bit at `group` index set to 1._

### toMask

```solidity
function toMask(uint8[] groups) internal pure returns (Masks.Mask)
```

_Returns a new mask with the bits at `groups` indices set to 1._

### get

```solidity
function get(Masks.Mask self, uint8 group) internal pure returns (bool)
```

_Get value of the mask at `group` index_

### isEmpty

```solidity
function isEmpty(Masks.Mask self) internal pure returns (bool)
```

_Whether the mask is `bytes32(0)`_

### complement

```solidity
function complement(Masks.Mask m1) internal pure returns (Masks.Mask)
```

_Invert the bits of a mask_

### union

```solidity
function union(Masks.Mask m1, Masks.Mask m2) internal pure returns (Masks.Mask)
```

_Perform a bitwise OR operation on two masks_

### intersection

```solidity
function intersection(Masks.Mask m1, Masks.Mask m2) internal pure returns (Masks.Mask)
```

_Perform a bitwise AND operation on two masks_

### difference

```solidity
function difference(Masks.Mask m1, Masks.Mask m2) internal pure returns (Masks.Mask)
```

_Perform a bitwise difference operation on two masks (m1 - m2)_

### symmetric_difference

```solidity
function symmetric_difference(Masks.Mask m1, Masks.Mask m2) internal pure returns (Masks.Mask)
```

_Returns the symmetric difference (∆) of two masks, also known as disjunctive union or exclusive OR (XOR)_

## ERC7739Signer

_Validates signatures wrapping the message hash in a nested EIP712 type. See {ERC7739Utils}.

Linking the signature to the EIP-712 domain separator is a security measure to prevent signature replay across different
EIP-712 domains (e.g. a single offchain owner of multiple contracts).

This contract requires implementing the {_validateSignature} function, which passes the wrapped message hash,
which may be either an typed data or a personal sign nested type.

NOTE: {EIP712} uses {ShortStrings} to optimize gas costs for short strings (up to 31 characters).
Consider that strings longer than that will use storage, which may limit the ability of the signer to
be used within the ERC-4337 validation phase (due to ERC-7562 storage access rules)._

### isValidSignature

```solidity
function isValidSignature(bytes32 hash, bytes signature) public view virtual returns (bytes4 result)
```

_Attempts validating the signature in a nested EIP-712 type.

A nested EIP-712 type might be presented in 2 different ways:

- As a nested EIP-712 typed data
- As a _personal_ signature (an EIP-712 mimic of the `eth_personalSign` for a smart contract)_

### _isValidSignature

```solidity
function _isValidSignature(bytes32 hash, bytes signature) internal view virtual returns (bool)
```

_Internal version of {isValidSignature} that returns a boolean._

### _isValidNestedPersonalSignSignature

```solidity
function _isValidNestedPersonalSignSignature(bytes32 hash, bytes signature) internal view virtual returns (bool)
```

_Nested personal signature verification._

### _isValidNestedTypedDataSignature

```solidity
function _isValidNestedTypedDataSignature(bytes32 hash, bytes encodedSignature) internal view virtual returns (bool)
```

_Nested EIP-712 typed data verification._

### _validateSignature

```solidity
function _validateSignature(bytes32 hash, bytes signature) internal view virtual returns (bool)
```

_Signature validation algorithm.

WARNING: Implementing a signature validation algorithm is a security-sensitive operation as it involves
cryptographic verification. It is important to review and test thoroughly before deployment. Consider
using one of the signature verification libraries ({ECDSA}, {P256} or {RSA})._

## ERC7739Utils

_Utilities to process https://ercs.ethereum.org/ERCS/erc-7739[ERC-7739] typed data signatures
that are specific to an EIP-712 domain.

This library provides methods to wrap, unwrap and operate over typed data signatures with a defensive
rehashing mechanism that includes the application's {EIP712-_domainSeparatorV4} and preserves
readability of the signed content using an EIP-712 nested approach.

A smart contract domain can validate a signature for a typed data structure in two ways:

- As an application validating a typed data signature. See {toNestedTypedDataHash}.
- As a smart contract validating a raw message signature. See {toNestedPersonalSignHash}.

NOTE: A provider for a smart contract wallet would need to return this signature as the
result of a call to `personal_sign` or `eth_signTypedData`, and this may be unsupported by
API clients that expect a return value of 129 bytes, or specifically the `r,s,v` parameters
of an {ECDSA} signature, as is for example specified for {EIP712}._

### InvalidContentsType

```solidity
error InvalidContentsType()
```

_Error when the contents type is invalid. See {tryValidateContentsType}._

### encodeTypedDataSig

```solidity
function encodeTypedDataSig(bytes signature, bytes32 appSeparator, bytes32 contentsHash, string contentsDescr) internal pure returns (bytes)
```

_Nest a signature for a given EIP-712 type into a nested signature for the domain of the app.

Counterpart of {decodeTypedDataSig} to extract the original signature and the nested components._

### decodeTypedDataSig

```solidity
function decodeTypedDataSig(bytes encodedSignature) internal pure returns (bytes signature, bytes32 appSeparator, bytes32 contentsHash, string contentsDescr)
```

_Parses a nested signature into its components.

Constructed as follows:

`signature ‖ DOMAIN_SEPARATOR ‖ contentsHash ‖ contentsDescr ‖ uint16(contentsDescr.length)`

- `signature` is the original signature for the nested struct hash that includes the "contents" hash
- `DOMAIN_SEPARATOR` is the EIP-712 {EIP712-_domainSeparatorV4} of the smart contract verifying the signature
- `contentsHash` is the hash of the underlying data structure or message
- `contentsDescr` is a descriptor of the "contents" part of the the EIP-712 type of the nested signature_

### personalSignStructHash

```solidity
function personalSignStructHash(bytes32 contents) internal pure returns (bytes32)
```

_Nests an `ERC-191` digest into a `PersonalSign` EIP-712 struct, and return the corresponding struct hash.
This struct hash must be combined with a domain separator, using {MessageHashUtils-toTypedDataHash} before
being verified/recovered.

This is used to simulates the `personal_sign` RPC method in the context of smart contracts._

### typedDataSignStructHash

```solidity
function typedDataSignStructHash(string contentsTypeName, string contentsType, bytes32 contentsHash, bytes domainBytes) internal pure returns (bytes32 result)
```

_Nests an `EIP-712` hash (`contents`) into a `TypedDataSign` EIP-712 struct, and return the corresponding
struct hash. This struct hash must be combined with a domain separator, using {MessageHashUtils-toTypedDataHash}
before being verified/recovered._

### typedDataSignStructHash

```solidity
function typedDataSignStructHash(string contentsDescr, bytes32 contentsHash, bytes domainBytes) internal pure returns (bytes32 result)
```

_Variant of {typedDataSignStructHash-string-string-bytes32-string-bytes} that takes a content descriptor
and decodes the `contentsTypeName` and `contentsType` out of it._

### typedDataSignTypehash

```solidity
function typedDataSignTypehash(string contentsTypeName, string contentsType) internal pure returns (bytes32)
```

_Compute the EIP-712 typehash of the `TypedDataSign` structure for a given type (and typename)._

### decodeContentsDescr

```solidity
function decodeContentsDescr(string contentsDescr) internal pure returns (string contentsTypeName, string contentsType)
```

_Parse the type name out of the ERC-7739 contents type description. Supports both the implicit and explicit
modes.

Following ERC-7739 specifications, a `contentsTypeName` is considered invalid if it's empty or it contains
any of the following bytes , )\x00

If the `contentsType` is invalid, this returns an empty string. Otherwise, the return string has non-zero
length._

