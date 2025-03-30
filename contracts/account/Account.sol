// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC7739} from "../utils/cryptography/ERC7739.sol";
import {AccountCore} from "./AccountCore.sol";

/**
 * @dev Extension of {AccountCore} with recommended feature that most account abstraction implementation will want:
 *
 * * {ERC721Holder} and {ERC1155Holder} to accept ERC-712 and ERC-1155 token transfers transfers.
 * * {ERC7739} for ERC-1271 signature support with ERC-7739 replay protection
 *
 * TIP: Use {ERC7821} to enable external calls in batches.
 *
 * NOTE: To use this contract, the {ERC7739-_rawSignatureValidation} function must be
 * implemented using a specific signature verification algorithm. See {SignerECDSA}, {SignerP256} or {SignerRSA}.
 */
abstract contract Account is AccountCore, ERC721Holder, ERC1155Holder, ERC7739 {}
