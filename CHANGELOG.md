## 23-06-2025

- `AxelarGatewayBase`, `AxelarGatewayDestination`, `AxelarGatewaySource`, `ERC7786Receiver` and `ERC7786Aggregator`: Changed support from CAIP addresses to ERC-7930 addresses.
- `ERC7786Aggregator`: Renamed to `ERC7786OpenBridge`.

## 20-06-2025

- `EnumerableMap`: Add `keys(uint256,uint256)` that returns a subset (slice) of the keys in the map.
- `EnumerableSet`: Add `values(uint256,uint256)` that returns a subset (slice) of the values in the set.

## 03-06-2025

- Moved `ERC7739Utils`, `ERC7913Utils`, `ZKEmailUtils`, abstract signers and ERC-7913 verifiers to `/contracts/utils/cryptography`

## 15-05-2025

- `ERC7579Multisig`: Add an abstract multisig module for ERC-7579 accounts using ERC-7913 signer keys.
- `ERC7579MultisigWeighted`: Add an abstract weighted multisig module that allows different weights to be assigned to signers.
- `ERC7579MultisigConfirmation`: Add an abstract confirmation-based multisig module that each signer to provide a confirmation signature.
- `ERC7579Executor`: Add an executor module that enables executing calls from accounts where the it's installed.
- `ERC7579DelayedExecutor`: Add executor module that adds a delay before executing an account operation.

## 06-05-2025

- `ERC7913ZKEmailVerifier`: Add ERC-7913 signature verifier that enables email-based authentication through zero-knowledge proofs.

## 05-05-2025

- `PaymasterERC20Guarantor`: Add extension of `PaymasterERC20` that enables third parties to guarantee user operations by prefunding gas costs upfront, with repayment handling for successful operations.
- `ERC7579Validator`: Add abstract validator module for ERC-7579 accounts that provides base implementation for signature validation.
- `ERC7579Signature`: Add implementation of `ERC7579Validator` that enables ERC-7579 accounts to integrate with address-less cryptographic keys and account signatures through ERC-7913 signature verification.

## 29-04-2025

- `ERC7913Utils`: Add `areValidSignaturesNow` function to verify multiple signatures from a set of ordered signers.

## 21-04-2025

- `MultiSignerERC7913`: Implementation of `AbstractSigner` that supports multiple ERC-7913 signers with a threshold-based signature verification system.
- `MultiSignerERC7913Weighted`: Extension of `MultiSignerERC7913` that supports assigning different weights to each signer, enabling more flexible governance schemes.

## 16-04-2025

- `ZKEmailUtils`: Add library for ZKEmail signature validation utilities that enables email-based authentication through zero-knowledge proofs, with support for DKIM verification and command template validation.
- `SignerZKEmail`: Add implementation of `AbstractSigner` that enables accounts to use ZKEmail signatures for authentication, leveraging DKIM registry and zero-knowledge proof verification.

## 12-04-2025

- `SignerERC7913`: Abstract signer that verifies signatures using the ERC-7913 workflow.
- `ERC7913P256Verifier` and `ERC7913RSAVerifier`: Ready to use ERC-7913 verifiers that implement key verification for P256 (secp256r1) and RSA keys.
- `ERC7913Utils`: Utilities library for verifying signatures by ERC-7913 formatted signers.

## 11-04-2025

- `EnumerableSetExtended` and `EnumerableMapExtended`: Extensions of the `EnumerableSet` and `EnumerableMap` libraries with more types, including non-value types.

## 03-04-2025

- `PaymasterERC20`: Extension of `PaymasterCore` that sponsors user operations against payment in ERC-20 tokens.
- `PaymasterERC721Owner`: Extension of `PaymasterCore` that approves sponsoring of user operation based on ownership of an ERC-721 NFT.

## 28-03-2025

- Deprecate `Account` and rename `AccountCore` to `Account`.
- Update `Account` and `Paymaster` to support entrypoint v0.8.0.

## 07-03-2025

- `ERC7786Aggregator`: Add an aggregator that implements a meta gateway on top of multiple ERC-7786 gateways.

## 31-01-2025

- `PaymasterCore`: Add a simple ERC-4337 paymaster implementation with minimal logic.
- `PaymasterSigner`: Extension of `PaymasterCore` that approves sponsoring of user operation based on a cryptographic signature verified by the paymaster.

## 15-01-2025

- `AccountCore`: Add an internal `_validateUserOp` function to validate user operations.
- `AccountERC7579`: Extension of `AccountCore` that implements support for ERC-7579 modules of type executor, validator, and fallback handler.
- `AccountERC7579Hooked`: Extension of `AccountERC7579` that implements support for ERC-7579 hook modules.

## 13-01-2025

- Rename `ERC7739Signer` into `ERC7739` to avoid confusion with the `AbstractSigner` family of contracts.
- Remove `AccountERC7821` in favor of `ERC7821`, an ERC-7821 implementation that doesn't rely on (but is compatible with) `AccountCore`.

## 23-12-2024

- `AccountERC7821`: Account implementation that implements ERC-7821 for minimal batch execution interface. No support for additional `opData` is included.

## 16-12-2024

- `AccountCore`: Added a simple ERC-4337 account implementation with minimal logic to process user operations.
- `Account`: Extensions of AccountCore with recommended features that most accounts should have.
- `AbstractSigner`, `SignerECDSA`, `SignerP256`, and `SignerRSA`: Add an abstract contract, and various implementations, for contracts that deal with signature verification. Used by AccountCore and `ERC7739Utils.
- `SignerERC7702`: Implementation of `AbstractSigner` for Externally Owned Accounts (EOAs). Useful with ERC-7702.

## 13-12-2024

- `ERC20Bridgeable`: Extension of ERC-20 that implements a minimal token interface for cross-chain transfers following ERC-7802.

## 29-11-2024

- `ERC7786Receiver`: ERC-7786 generic cross-chain message receiver contract.
- `AxelarGatewayBase`: Cross-chain gateway adapter for the Axelar Network following ERC-7786 that tracks destination gateways and CAIP-2 equivalences.
- `AxelarGatewayDestination`: ERC-7786 gateway destination adapter for the Axelar Network used to receive cross-chain messages.
- `AxelarGatewaySource`: ERC-7786 gateway source adapter for the Axelar Network used to send cross-chain messages.
- `AxelarGatewayDuplex`: Both a destination and source adapter following ERC-7786 for the Axelar Network used to send and receive cross-chain messages.

## 06-11-2024

- `ERC7739Utils`: Add a library that implements a defensive rehashing mechanism to prevent replayability of smart contract signatures based on the ERC-7739.
- `ERC7739Signer`: An abstract contract to validate signatures following the rehashing scheme from `ERC7739Utils`.

## 15-10-2024

- `ERC20Collateral`: Extension of ERC-20 that limits the supply of tokens based on a collateral and time-based expiration.

## 10-10-2024

- `ERC20Allowlist`: Extension of ERC-20 that implements an allow list to enable token transfers, disabled by default.
- `ERC20Blocklist`: Extension of ERC-20 that implements a block list to restrict token transfers, enabled by default.
- `ERC20Custodian`: Extension of ERC-20 that allows a custodian to freeze user's tokens by a certain amount.

## 03-10-2024

- `OnTokenTransferAdapter`: An adapter that exposes `transferAndCall` on top of an ERC-1363 receiver.

## 15-05-2024

- `HybridProxy`: Add a proxy contract that can either use a beacon to retrieve the implementation or fallback to an address in the ERC-1967's implementation slot.

## 11-05-2024

- `AccessManagerLight`: Add a simpler version of the `AccessManager` in OpenZeppelin Contracts.
- `ERC4626Fees`: Extension of ERC-4626 that implements fees on entry and exit from the vault.
- `Masks`: Add library to handle `bytes32` masks.
