// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155HolderLean, IERC1155Receiver} from "../token/ERC1155/utils/ERC1155HolderLean.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {RSA} from "@openzeppelin/contracts/utils/cryptography/RSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {AccountBase} from "./draft-AccountBase.sol";
import {ERC7739Signer} from "../utils/cryptography/draft-ERC7739Signer.sol";

/**
 * @dev Account implementation using {RSA} signatures and {ERC7739Signer} for replay protection.
 *
 * NOTE: Storing `_e` and `_n` in regular storage violate ERC-7562 validation rules if the contract
 * is used as an ERC-1271 signer during the validation phase of a different account contract.
 * Consider deploying this contract through a factory that sets `_e` and `_n` as immutable arguments
 * (see {Clones-cloneDeterministicWithImmutableArgs}).
 */
abstract contract AccountRSA is ERC165, ERC7739Signer, ERC721Holder, ERC1155HolderLean, AccountBase {
    using MessageHashUtils for bytes32;

    /**
     * @dev The {signer} is already initialized.
     */
    error AccountP256UninitializedSigner(bytes e, bytes n);

    bytes private _e;
    bytes private _n;

    /**
     * @dev Initializes the account with the RSA public key.
     */
    function _initializeSigner(bytes memory e, bytes memory n) internal {
        if (_e.length != 0 || _n.length != 0) revert AccountP256UninitializedSigner(e, n);
        _e = e;
        _n = n;
    }

    /**
     * @dev Return the account's signer RSA public key.
     */
    function signer() public view virtual returns (bytes memory e, bytes memory n) {
        return (_e, _n);
    }

    /**
     * @dev Returns the ERC-191 signed `userOpHash` hashed with keccak256 using `personal_sign`.
     */
    function _userOpSignedHash(
        PackedUserOperation calldata /* userOp */,
        bytes32 userOpHash
    ) internal view virtual override returns (bytes32) {
        return userOpHash.toEthSignedMessageHash();
    }

    /**
     * @dev Internal version of {validateUserOp} that relies on {_validateNestedEIP712Signature}.
     *
     * The `userOpSignedHash` is the digest from {_userOpSignedHash}.
     *
     * NOTE: To override the signature functionality, try overriding {_validateNestedEIP712Signature} instead.
     */
    function _validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpSignedHash
    ) internal view virtual override returns (uint256) {
        return
            _isValidSignature(userOpSignedHash, userOp.signature)
                ? ERC4337Utils.SIG_VALIDATION_SUCCESS
                : ERC4337Utils.SIG_VALIDATION_FAILED;
    }

    /**
     * @dev Validates the signature using the account's signer.
     *
     * This function provides a nested EIP-712 hash. Developers must override only this
     * function to ensure no raw message signing is possible.
     */
    function _validateNestedEIP712Signature(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        (bytes memory e, bytes memory n) = signer();
        return RSA.pkcs1Sha256(abi.encodePacked(hash), signature, e, n);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }
}
