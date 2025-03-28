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
