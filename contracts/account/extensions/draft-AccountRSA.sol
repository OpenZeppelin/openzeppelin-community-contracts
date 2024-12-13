// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {RSA} from "@openzeppelin/contracts/utils/cryptography/RSA.sol";
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
    bytes32 internal constant _PACKED_USER_OPERATION =
        keccak256(
            "PackedUserOperation(address sender,uint256 nonce,bytes initCode,bytes callData,bytes32 accountGasLimits,uint256 preVerificationGas,bytes32 gasFees,bytes paymasterAndData,address entrypoint)"
        );

    /**
     * @dev The {signer} is already initialized.
     */
    error AccountRSAUninitializedSigner(bytes e, bytes n);

    bytes private _e;
    bytes private _n;

    /**
     * @dev Initializes the account with the RSA public key. This function can be called only once.
     */
    function _initializeSigner(bytes memory e, bytes memory n) internal {
        if (_e.length != 0 || _n.length != 0) revert AccountRSAUninitializedSigner(e, n);
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
     * @dev Customize the user operation hash to sign. See {AccountBase-_signableUserOpHash}.
     *
     * This implementation uses the EIP-712 typed data hashing mechanism for readability.
     */
    function _signableUserOpHash(
        PackedUserOperation calldata userOp,
        bytes32 /* userOpHash */
    ) internal view virtual override returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        _PACKED_USER_OPERATION,
                        userOp.sender,
                        userOp.nonce,
                        keccak256(userOp.initCode),
                        keccak256(userOp.callData),
                        userOp.accountGasLimits,
                        userOp.preVerificationGas,
                        userOp.gasFees,
                        keccak256(userOp.paymasterAndData),
                        msg.sender
                    )
                )
            );
    }

    /**
     * @dev Validates the signature using the account's signer.
     */
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        (bytes memory e, bytes memory n) = signer();
        return RSA.pkcs1Sha256(abi.encodePacked(hash), signature, e, n);
    }
}
