// contracts/MyAccount.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "@openzeppelin/community-contracts/account/Account.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC7739} from "@openzeppelin/community-contracts/utils/cryptography/ERC7739.sol";
import {ERC7821} from "@openzeppelin/community-contracts/account/extensions/ERC7821.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SignerRSA} from "@openzeppelin/community-contracts/utils/cryptography/SignerRSA.sol";

contract MyAccountRSA is Account, SignerRSA, ERC7739, ERC7821, ERC721Holder, ERC1155Holder, Initializable {
    constructor() EIP712("MyAccountRSA", "1") {}

    function initialize(bytes memory e, bytes memory n) public initializer {
        _setSigner(e, n);
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
