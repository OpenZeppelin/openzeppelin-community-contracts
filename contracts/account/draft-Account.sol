// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC7739Signer} from "../utils/cryptography/draft-ERC7739Signer.sol";
import {AccountCore} from "./draft-AccountCore.sol";

/**
 * @dev Extention of {AccountCore} with recommanded feature that most account abstraction implementation will want:
 *
 * * {ERC721Holder} for ERC-721 token handling
 * * {ERC1155Holder} for ERC-1155 token handling
 * * {ERC7739Signer} for ERC-1271 signature support with ERC-7739 replay protection
 */
abstract contract Account is AccountCore, ERC721Holder, ERC1155Holder, ERC7739Signer {
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(AccountCore, ERC7739Signer) returns (bool);
}
