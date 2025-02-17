// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {AccountCore} from "../../account/AccountCore.sol";
import {Account} from "../../account/Account.sol";
import {AccountERC7579} from "../../account/extensions/AccountERC7579.sol";
import {ERC7821} from "../../account/extensions/ERC7821.sol";
import {AbstractSigner} from "../../utils/cryptography/AbstractSigner.sol";
import {ERC1271} from "../../utils/cryptography/ERC1271.sol";
import {SignerERC7702} from "../../utils/cryptography/SignerERC7702.sol";

abstract contract AccountERC7702WithModulesMock is Account, AccountERC7579, SignerERC7702 {
    function _validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal virtual override(AccountCore, AccountERC7579) returns (uint256) {
        return super._validateUserOp(userOp, userOpHash);
    }

    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) public view virtual override(ERC1271, Account) returns (bytes4) {
        return super.isValidSignature(hash, signature);
    }

    /// @dev Override the default ERC-1271 (included in Account) with ERC-7739.
    function _isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(Account, AccountERC7579) returns (bool) {
        return super._isValidSignature(hash, signature);
    }

    /// @dev Enable signature using the ERC-7702 signer.
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(AbstractSigner, AccountERC7579, SignerERC7702) returns (bool) {
        return SignerERC7702._rawSignatureValidation(hash, signature);
    }
}
