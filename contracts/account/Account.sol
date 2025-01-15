// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {ERC7739} from "../utils/cryptography/ERC7739.sol";
import {AccountCore} from "./AccountCore.sol";

/**
 * @dev Extension of {AccountCore} with recommended feature that most account abstraction implementation will want:
 *
 * * {ERC721Holder} and {ERC1155Holder} to accept ERC-712 and ERC-1155 token transfers transfers.
 * * {ERC7739} for ERC-1271 signature support with ERC-7739 replay protection
 * * {ERC7821} for performing external calls in batches.
 *
 * TIP: Use {ERC7821} to enable external calls in batches.
 *
 * NOTE: To use this contract, the {ERC7739-_rawSignatureValidation} function must be
 * implemented using a specific signature verification algorithm. See {SignerECDSA}, {SignerP256} or {SignerRSA}.
 */
abstract contract Account is AccountCore, EIP712, ERC721Holder, ERC1155Holder, ERC7739 {
    bytes32 internal constant _PACKED_USER_OPERATION =
        keccak256(
            "PackedUserOperation(address sender,uint256 nonce,bytes initCode,bytes callData,bytes32 accountGasLimits,uint256 preVerificationGas,bytes32 gasFees,bytes paymasterAndData)"
        );

    /**
     * @dev Specialization of {AccountCore-_signableUserOpHash} that returns a typehash following EIP-712 typed data
     * hashing for readability. This assumes the underlying signature scheme implements `signTypedData`, which will be
     * the case when combined with {SignerECDSA} or {SignerERC7702}.
     */
    function _signableUserOpHash(
        PackedUserOperation calldata userOp,
        bytes32 /*userOpHash*/
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
                        keccak256(userOp.paymasterAndData)
                    )
                )
            );
    }
}
