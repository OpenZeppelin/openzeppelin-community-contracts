// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ECDSAOwnedDKIMRegistry} from "@zk-email/email-tx-builder/utils/ECDSAOwnedDKIMRegistry.sol";
import {Groth16Verifier} from "@zk-email/email-tx-builder/utils/Groth16Verifier.sol";
import {Verifier} from "@zk-email/email-tx-builder/utils/Verifier.sol";
