// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ECDSAOwnedDKIMRegistry} from "@zk-email/email-tx-builder/src/utils/ECDSAOwnedDKIMRegistry.sol";

// Hardhat 3 only emits artifacts for contracts declared in a compilation root. The exposed version of
// `ECDSAOwnedDKIMRegistry` can't be used instead: its constructor runs the initializer, so `initialize` can't be called.
contract ECDSAOwnedDKIMRegistryMock is ECDSAOwnedDKIMRegistry {}
