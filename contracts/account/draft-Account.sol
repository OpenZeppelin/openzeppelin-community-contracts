// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC7739Signer} from "../utils/cryptography/draft-ERC7739Signer.sol";
import {AccountCore} from "./draft-AccountCore.sol";

abstract contract Account is AccountCore, ERC721Holder, ERC1155Holder, ERC7739Signer {
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(AccountCore, ERC7739Signer) returns (bool);
}
