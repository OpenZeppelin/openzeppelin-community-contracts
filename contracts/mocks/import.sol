// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

// This file forces the compilation of contracts that are only used (as artifacts) in tests.
// forge-lint: disable-start(unused-import)
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccountERC7913Mock} from "@openzeppelin/contracts/mocks/account/AccountMock.sol";
import {ERC20Reentrant} from "@openzeppelin/contracts/mocks/token/ERC20Reentrant.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
// forge-lint: disable-end(unused-import)
