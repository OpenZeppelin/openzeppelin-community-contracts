// contracts/MyAccountERC7913.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Account} from "@openzeppelin/contracts/account/Account.sol";
import {ERC7821} from "@openzeppelin/contracts/account/extensions/draft-ERC7821.sol";
import {ERC7739} from "@openzeppelin/contracts/utils/cryptography/signers/draft-ERC7739.sol";
import {SignerERC7913} from "@openzeppelin/contracts/utils/cryptography/signers/SignerERC7913.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract MyAccountERC7913 is Account, SignerERC7913, ERC7739, ERC7821, ERC721Holder, ERC1155Holder, Initializable {
    constructor(bytes memory signer) EIP712("MyAccount7913", "1") SignerERC7913(signer) {}

    function initialize(bytes memory signer) public initializer {
        _setSigner(signer);
    }

    /// @dev Allows the entry point as an authorized executor.
    function _erc7821AuthorizedExecutor(
        address caller,
        bytes32 mode,
        bytes calldata executionData
    ) internal view virtual override returns (bool) {
        return caller == address(entryPoint()) || super._erc7821AuthorizedExecutor(caller, mode, executionData);
    }
}
