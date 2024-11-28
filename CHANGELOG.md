## 06-11-2024

* `ERC7739Utils`: Add a library that implements a defensive rehashing mechanism to prevent replayability of smart contract signatures based on the ERC-7739.
* `ERC7739Signer`: An abstract contract to validate signatures following the rehashing scheme from `ERC7739Utils`.

## 15-10-2024

* `ERC20Collateral`: Extension of ERC-20 that limits the supply of tokens based on a collateral and time-based expiration.

## 10-10-2024

* `ERC20Allowlist`: Extension of ERC-20 that implements an allow list to enable token transfers, disabled by default.
* `ERC20Blocklist`: Extension of ERC-20 that implements a block list to restrict token transfers, enabled by default.
* `ERC20Custodian`: Extension of ERC-20 that allows a custodian to freeze user's tokens by a certain amount.

## 03-10-2024

* `OnTokenTransferAdapter`: An adapter that exposes `transferAndCall` on top of an ERC-1363 receiver.

## 15-05-2024

* `HybridProxy`: Add a proxy contract that can either use a beacon to retrieve the implementation or fallback to an address in the ERC-1967's implementation slot.

## 11-05-2024

* `AccessManagerLight`: Add a simpler version of the `AccessManager` in OpenZeppelin Contracts.
* `ERC4626Fees`: Extension of ERC-4626 that implements fees on entry and exit from the vault.
* `Masks`: Add library to handle `bytes32` masks.

