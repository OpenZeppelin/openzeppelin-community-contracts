// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ECDSAOwnedDKIMRegistry} from "@zk-email/email-tx-builder/utils/ECDSAOwnedDKIMRegistry.sol";
import {ERC1271WalletMock} from "@openzeppelin/contracts/mocks/ERC1271WalletMock.sol";
