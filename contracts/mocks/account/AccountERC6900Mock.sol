// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {AccountERC6900} from "../../account/extensions/AccountERC6900.sol";

abstract contract AccountERC6900Mock is EIP712, AccountERC6900 {
    bytes32 internal constant _PACKED_USER_OPERATION =
        keccak256(
            "PackedUserOperation(address sender,uint256 nonce,bytes initCode,bytes callData,bytes32 accountGasLimits,uint256 preVerificationGas,bytes32 gasFees,bytes paymasterAndData)"
        );

    constructor(address validator, bytes memory initData) {
        // _installModule(MODULE_TYPE_VALIDATOR, validator, initData);
    }

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
