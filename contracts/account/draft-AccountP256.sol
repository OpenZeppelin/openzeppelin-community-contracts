// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {P256} from "@openzeppelin/contracts/utils/cryptography/P256.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {AccountERC7739} from "./extensions/draft-AccountERC7739.sol";

/**
 * @dev Account implementation using {P256} signatures and {AccountERC7739} for replay protection.
 *
 * An {_initializeSigner} function is provided to set the account's signer address. Doing so it's
 * easier for a factory, whose likely to use initializable clones of this contract.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyAccountP256 is AccountP256 {
 *     constructor() EIP712("MyAccountP256", "1") {}
 *
 *     function initializeSigner(bytes32 qx, bytes32 qy) public virtual initializer {
 *       // Will revert if the signer is already initialized
 *       _initializeSigner(qx, qy);
 *     }
 * }
 * ```
 *
 * IMPORTANT: Avoiding to call {_initializeSigner} either during construction (if used standalone)
 * or during initialization (if used as a clone) may leave the account either front-runnable or unusable.
 */
abstract contract AccountP256 is AccountERC7739, ERC721Holder, ERC1155Holder {
    using MessageHashUtils for bytes32;

    /**
     * @dev The {signer} is already initialized.
     */
    error AccountP256UninitializedSigner(bytes32 qx, bytes32 qy);

    bytes32 private _qx;
    bytes32 private _qy;

    /**
     * @dev Initializes the account with the P256 public key. This function can be called only once.
     */
    function _initializeSigner(bytes32 qx, bytes32 qy) internal {
        if (_qx != 0 || _qy != 0) revert AccountP256UninitializedSigner(qx, qy);
        _qx = qx;
        _qy = qy;
    }

    /**
     * @dev Return the account's signer P256 public key.
     */
    function signer() public view virtual returns (bytes32 qx, bytes32 qy) {
        return (_qx, _qy);
    }

    /**
     * @dev Returns the ERC-191 signed `userOpHash` hashed with keccak256 using `personal_sign`.
     */
    function _validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view virtual override returns (uint256) {
        return super._validateUserOp(userOp, userOpHash.toEthSignedMessageHash());
    }

    /**
     * @dev Validates the signature using the account's signer.
     *
     * This function provides a nested EIP-712 hash. Developers must override only this
     * function to ensure no raw message signing is possible.
     */
    function _validateSignature(bytes32 hash, bytes calldata signature) internal view virtual override returns (bool) {
        if (signature.length < 0x40) return false;
        bytes32 r = bytes32(signature[0x00:0x20]);
        bytes32 s = bytes32(signature[0x20:0x40]);
        (bytes32 qx, bytes32 qy) = signer();
        return P256.verify(hash, r, s, qx, qy);
    }

    /// @inheritdoc ERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, ERC1155Holder) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
