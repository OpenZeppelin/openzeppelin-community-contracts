// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {MODULE_TYPE_VALIDATOR} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {SignerERC7702} from "../../utils/cryptography/SignerERC7702.sol";
import {AccountERC7579} from "../../account/extensions/AccountERC7579.sol";

abstract contract AccountERC7702WithModulesMock is EIP712, AccountERC7579, SignerERC7702 {
    bytes32 internal constant _PACKED_USER_OPERATION =
        keccak256(
            "PackedUserOperation(address sender,uint256 nonce,bytes initCode,bytes callData,bytes32 accountGasLimits,uint256 preVerificationGas,bytes32 gasFees,bytes paymasterAndData)"
        );

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

    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(AccountERC7579, SignerERC7702) returns (bool) {
        // Try ERC-7702 first, and fallback to ERC-7579
        return
            SignerERC7702._rawSignatureValidation(hash, signature) ||
            AccountERC7579._rawSignatureValidation(hash, signature);
    }
}
