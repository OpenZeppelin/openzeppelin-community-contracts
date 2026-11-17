// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

// This file lists the dependencies that the tests deploy. Hardhat 3 only emits artifacts for compilation roots, so
// these contracts get no artifact of their own. Importing them by name (with `exposed.imports`) makes the exposed
// plugin generate their `$`-prefixed versions, which are roots: the tests deploy these.
// forge-lint: disable-start(unused-import)
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccountERC7913Mock} from "@openzeppelin/contracts/mocks/account/AccountMock.sol";
import {ERC20Reentrant} from "@openzeppelin/contracts/mocks/token/ERC20Reentrant.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {CallReceiverMock} from "@openzeppelin/contracts/mocks/CallReceiverMock.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC7913P256Verifier} from "@openzeppelin/contracts/utils/cryptography/verifiers/ERC7913P256Verifier.sol";
import {ERC7913RSAVerifier} from "@openzeppelin/contracts/utils/cryptography/verifiers/ERC7913RSAVerifier.sol";
// forge-lint: disable-end(unused-import)
