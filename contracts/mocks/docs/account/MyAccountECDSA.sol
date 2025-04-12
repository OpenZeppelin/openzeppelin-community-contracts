// contracts/MyAccount.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../../account/Account.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC7739} from "../../../utils/cryptography/ERC7739.sol";
import {ERC7821} from "../../../account/extensions/ERC7821.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {SignerECDSA} from "../../../utils/cryptography/SignerECDSA.sol";

contract MyAccountECDSA is Account, SignerECDSA, ERC7739, ERC7821, ERC721Holder, ERC1155Holder, Initializable {
    constructor() EIP712("MyAccountECDSA", "1") {}

    function initialize(address signerAddr) public initializer {
        _setSigner(signerAddr);
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
