// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC7739Signer} from "../utils/cryptography/ERC7739Signer.sol";
import {AccountCore} from "./AccountCore.sol";
import {AccountERC7821} from "./extensions/AccountERC7821.sol";

/**
 * @dev Extension of {AccountCore} with recommended feature that most account abstraction implementation will want:
 *
 * * {AccountERC7821} for performing external calls in batches.
 * * {ERC721Holder} and {ERC1155Holder} to accept ERC-712 and ERC-1155 token transfers transfers.
 * * {ERC7739Signer} for ERC-1271 signature support with ERC-7739 replay protection
 *
 * NOTE: To use this contract, the {ERC7739Signer-_rawSignatureValidation} function must be
 * implemented using a specific signature verification algorithm. See {SignerECDSA}, {SignerP256} or {SignerRSA}.
 */
abstract contract Account is AccountCore, AccountERC7821, ERC721Holder, ERC1155Holder, ERC7739Signer {}
