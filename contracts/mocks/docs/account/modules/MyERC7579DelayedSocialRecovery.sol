// contracts/MyERC7579DelayedSocialRecovery.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Calldata} from "@openzeppelin/contracts/utils/Calldata.sol";
import {ERC7579DelayedExecutor} from "../../../../account/modules/ERC7579DelayedExecutor.sol";
import {ERC7579Multisig} from "../../../../account/modules/ERC7579Multisig.sol";

abstract contract MyERC7579DelayedSocialRecovery is EIP712, ERC7579DelayedExecutor, ERC7579Multisig {
    bytes32 private constant RECOVER_TYPEHASH =
        keccak256("Recover(address account,bytes32 salt,bytes32 mode,bytes executionCalldata)");

    // Data encoding: [uint16(executorArgsLength), executorArgs, uint16(multisigArgsLength), multisigArgs]
    function onInstall(bytes calldata data) public override(ERC7579DelayedExecutor, ERC7579Multisig) {
        uint16 executorArgsLength = uint16(uint256(bytes32(data[0:2]))); // First 2 bytes are the length
        bytes calldata executorArgs = data[2:2 + executorArgsLength]; // Next bytes are the args
        uint16 multisigArgsLength = uint16(uint256(bytes32(data[2 + executorArgsLength:]))); // Next 2 bytes are the length
        bytes calldata multisigArgs = data[2 + executorArgsLength + 2:2 + executorArgsLength + 2 + multisigArgsLength]; // Next bytes are the args

        ERC7579DelayedExecutor.onInstall(executorArgs);
        ERC7579Multisig.onInstall(multisigArgs);
    }

    function onUninstall(bytes calldata) public override(ERC7579DelayedExecutor, ERC7579Multisig) {
        ERC7579DelayedExecutor.onUninstall(Calldata.emptyBytes());
        ERC7579Multisig.onUninstall(Calldata.emptyBytes());
    }

    // Data encoding: [uint16(executionCalldataLength), executionCalldata, signature]
    function _validateSchedule(
        address account,
        bytes32 salt,
        bytes32 mode,
        bytes calldata data
    ) internal override returns (bool) {
        uint16 executionCalldataLength = uint16(uint256(bytes32(data[0:2]))); // First 2 bytes are the length
        bytes calldata executionCalldata = data[2:2 + executionCalldataLength]; // Next bytes are the calldata
        bytes calldata signature = data[2 + executionCalldataLength:]; // Remaining bytes are the signature
        return
            _validateMultisignature(account, _getExecuteTypeHash(account, salt, mode, executionCalldata), signature) ||
            super._validateSchedule(account, salt, mode, data);
    }

    function _getExecuteTypeHash(
        address account,
        bytes32 salt,
        bytes32 mode,
        bytes calldata executionCalldata
    ) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(RECOVER_TYPEHASH, account, salt, mode, executionCalldata)));
    }
}
