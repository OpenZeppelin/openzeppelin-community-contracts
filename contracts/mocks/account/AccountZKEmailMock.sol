// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Account} from "@openzeppelin/contracts/account/Account.sol";
import {ERC7821} from "@openzeppelin/contracts/account/extensions/draft-ERC7821.sol";
import {ERC7739, EIP712} from "@openzeppelin/contracts/utils/cryptography/signers/draft-ERC7739.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {SignerZKEmail} from "../../utils/cryptography/signers/SignerZKEmail.sol";
import {IDKIMRegistry} from "@zk-email/contracts/DKIMRegistry.sol";
import {IGroth16Verifier} from "@zk-email/email-tx-builder/src/interfaces/IGroth16Verifier.sol";

contract AccountZKEmailMock is Account, SignerZKEmail, ERC7739, ERC7821, ERC721Holder, ERC1155Holder {
    constructor(
        bytes32 accountSalt_,
        IDKIMRegistry registry_,
        IGroth16Verifier groth16Verifier_
    ) EIP712("AccountZKEmailMock", "1") {
        _setAccountSalt(accountSalt_);
        _setDKIMRegistry(registry_);
        _setVerifier(groth16Verifier_);
    }

    /// @inheritdoc ERC7821
    function _erc7821AuthorizedExecutor(
        address caller,
        bytes32 mode,
        bytes calldata executionData
    ) internal view virtual override returns (bool) {
        return caller == address(entryPoint()) || super._erc7821AuthorizedExecutor(caller, mode, executionData);
    }
}
