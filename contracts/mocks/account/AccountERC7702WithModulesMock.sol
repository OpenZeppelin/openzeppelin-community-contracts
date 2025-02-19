// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {AccountCore} from "../../account/AccountCore.sol";
import {Account} from "../../account/Account.sol";
import {AccountERC7579} from "../../account/extensions/AccountERC7579.sol";
import {ERC7821} from "../../account/extensions/ERC7821.sol";
import {AbstractSigner} from "../../utils/cryptography/AbstractSigner.sol";
import {SignerERC7702} from "../../utils/cryptography/SignerERC7702.sol";

abstract contract AccountERC7702WithModulesMock is Account, AccountERC7579, SignerERC7702 {
    function _validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal virtual override(AccountCore, AccountERC7579) returns (uint256) {
        return super._validateUserOp(userOp, userOpHash);
    }

    /// @dev Resolve the ERC-7739 (from Account) and the ERC-7579 (from AccountERC7579) to support both schemes.
    function isValidSignature(
        bytes32 hash,
        bytes calldata signature
    ) public view virtual override(Account, AccountERC7579) returns (bytes4) {
        // ERC-7739 can return the fn selector (success), 0xffffffff (invalid) or 0x77390001 (detection).
        // If the return is 0xffffffff, we fallback to validation using ERC-7579 modules.
        bytes4 erc7739magic = Account.isValidSignature(hash, signature);
        return erc7739magic == bytes4(0xffffffff) ? AccountERC7579.isValidSignature(hash, signature) : erc7739magic;
    }

    /// @dev Enable signature using the ERC-7702 signer.
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(AbstractSigner, AccountERC7579, SignerERC7702) returns (bool) {
        return SignerERC7702._rawSignatureValidation(hash, signature);
    }
}
