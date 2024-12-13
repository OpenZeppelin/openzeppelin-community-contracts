// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {RSA} from "@openzeppelin/contracts/utils/cryptography/RSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {AccountBase} from "../draft-AccountBase.sol";

/**
 * @dev Account implementation using {RSA} signatures and {AccountBase} for replay protection.
 *
 * An {_initializeSigner} function is provided to set the account's signer address. Doing so it's
 * easier for a factory, whose likely to use initializable clones of this contract.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyAccountRSA is AccountRSA {
 *     constructor() EIP712("MyAccountRSA", "1") {}
 *
 *     function initializeSigner(bytes memory e, bytes memory n) external {
 *       // Will revert if the signer is already initialized
 *       _initializeSigner(e, n);
 *     }
 * }
 * ```
 *
 * IMPORTANT: Avoiding to call {_initializeSigner} either during construction (if used standalone)
 * or during initialization (if used as a clone) may leave the account either front-runnable or unusable.
 */
abstract contract AccountRSA is AccountBase, ERC721Holder, ERC1155Holder {
    using MessageHashUtils for bytes32;

    /**
     * @dev The {signer} is already initialized.
     */
    error AccountP256UninitializedSigner(bytes e, bytes n);

    bytes private _e;
    bytes private _n;

    /**
     * @dev Initializes the account with the RSA public key. This function can be called only once.
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
    function _validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal virtual override returns (uint256) {
        return super._validateUserOp(userOp, userOpHash.toEthSignedMessageHash());
    }

    /**
     * @dev Validates the signature using the account's signer.
     *
     * This function provides a nested EIP-712 hash. Developers must override only this
     * function to ensure no raw message signing is possible.
     */
    function _validateSignature(bytes32 hash, bytes calldata signature) internal view virtual override returns (bool) {
        (bytes memory e, bytes memory n) = signer();
        return RSA.pkcs1Sha256(abi.encodePacked(hash), signature, e, n);
    }
}
