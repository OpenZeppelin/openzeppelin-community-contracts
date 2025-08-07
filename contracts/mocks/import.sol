// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ECDSAOwnedDKIMRegistry} from "@zk-email/email-tx-builder/src/utils/ECDSAOwnedDKIMRegistry.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {
    AccountECDSAMock,
    AccountERC7579Mock,
    AccountERC7913Mock
} from "@openzeppelin/contracts/mocks/account/AccountMock.sol";
import {ERC1271WalletMock} from "@openzeppelin/contracts/mocks/ERC1271WalletMock.sol";
import {CallReceiverMock} from "@openzeppelin/contracts/mocks/CallReceiverMock.sol";
import {ERC7913P256Verifier} from "@openzeppelin/contracts/utils/cryptography/verifiers/ERC7913P256Verifier.sol";
import {ERC7913RSAVerifier} from "@openzeppelin/contracts/utils/cryptography/verifiers/ERC7913RSAVerifier.sol";
