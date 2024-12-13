// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {AccountBase} from "../draft-AccountBase.sol";

/**
 * @dev Account implementation using {ECDSA} signatures and {AccountBase} for replay protection.
 *
 * An {_initializeSigner} function is provided to set the account's signer address. Doing so it's
 * easier for a factory, whose likely to use initializable clones of this contract.
 *
 * Example of usage:
 *
 * ```solidity
 * contract MyAccountECDSA is AccountECDSA {
 *     constructor() EIP712("MyAccountECDSA", "1") {}
 *
 *     function initializeSigner(address signerAddr) public virtual initializer {
 *       // Will revert if the signer is already initialized
 *       _initializeSigner(signerAddr);
 *     }
 * }
 * ```
 *
 * IMPORTANT: Avoiding to call {_initializeSigner} either during construction (if used standalone)
 * or during initialization (if used as a clone) may leave the account either front-runnable or unusable.
 */
abstract contract AccountECDSA is AccountBase, ERC721Holder, ERC1155Holder {
    bytes32 internal constant _PACKED_USER_OPERATION =
        keccak256(
            "PackedUserOperation(address sender,uint256 nonce,bytes initCode,bytes callData,bytes32 accountGasLimits,uint256 preVerificationGas,bytes32 gasFees,bytes paymasterAndData,address entrypoint)"
        );

    /**
     * @dev The {signer} is already initialized.
     */
    error AccountECDSAUninitializedSigner(address signer);

    address private _signer;

    /**
     * @dev Initializes the account with the address of the native signer. This function can be called only once.
     */
    function _initializeSigner(address signerAddr) internal {
        if (_signer != address(0)) revert AccountECDSAUninitializedSigner(signerAddr);
        _signer = signerAddr;
    }

    /**
     * @dev Return the account's signer address.
     */
    function signer() public view virtual returns (address) {
        return _signer;
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
        (address recovered, ECDSA.RecoverError err, ) = ECDSA.tryRecover(hash, signature);
        return signer() == recovered && err == ECDSA.RecoverError.NoError;
    }
}
