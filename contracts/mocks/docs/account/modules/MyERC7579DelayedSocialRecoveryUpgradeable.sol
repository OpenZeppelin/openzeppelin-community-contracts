// contracts/MyERC7579DelayedSocialRecovery.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ERC7579ExecutorUpgradeable} from "../../../../account/modules/ERC7579ExecutorUpgradeable.sol";
import {ERC7579ValidatorUpgradeable} from "../../../../account/modules/ERC7579ValidatorUpgradeable.sol";
import {Calldata} from "@openzeppelin/contracts/utils/Calldata.sol";
import {ERC7579DelayedExecutorUpgradeable} from "../../../../account/modules/ERC7579DelayedExecutorUpgradeable.sol";
import {ERC7579MultisigUpgradeable} from "../../../../account/modules/ERC7579MultisigUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract MyERC7579DelayedSocialRecoveryUpgradeable is Initializable, EIP712Upgradeable, ERC7579DelayedExecutorUpgradeable, ERC7579MultisigUpgradeable {
    bytes32 private constant RECOVER_TYPEHASH =
        keccak256("Recover(address account,bytes32 salt,bytes32 mode,bytes executionCalldata)");

    function __MyERC7579DelayedSocialRecovery_init() internal onlyInitializing {
    }

    function __MyERC7579DelayedSocialRecovery_init_unchained() internal onlyInitializing {
    }
    function isModuleType(uint256 moduleTypeId) public pure override(ERC7579ExecutorUpgradeable, ERC7579ValidatorUpgradeable) returns (bool) {
        return ERC7579ExecutorUpgradeable.isModuleType(moduleTypeId) || ERC7579ExecutorUpgradeable.isModuleType(moduleTypeId);
    }

    // Data encoding: [uint16(executorArgsLength), executorArgs, uint16(multisigArgsLength), multisigArgs]
    function onInstall(bytes calldata data) public override(ERC7579DelayedExecutorUpgradeable, ERC7579MultisigUpgradeable) {
        uint16 executorArgsLength = uint16(bytes2(data[0:2])); // First 2 bytes are the length
        bytes calldata executorArgs = data[2:2 + executorArgsLength]; // Next bytes are the args
        uint16 multisigArgsLength = uint16(bytes2(data[2 + executorArgsLength:4 + executorArgsLength])); // Next 2 bytes are the length
        bytes calldata multisigArgs = data[4 + executorArgsLength:4 + executorArgsLength + multisigArgsLength]; // Next bytes are the args

        ERC7579DelayedExecutorUpgradeable.onInstall(executorArgs);
        ERC7579MultisigUpgradeable.onInstall(multisigArgs);
    }

    function onUninstall(bytes calldata) public override(ERC7579DelayedExecutorUpgradeable, ERC7579MultisigUpgradeable) {
        ERC7579DelayedExecutorUpgradeable.onUninstall(Calldata.emptyBytes());
        ERC7579MultisigUpgradeable.onUninstall(Calldata.emptyBytes());
    }

    // Data encoding: [uint16(executionCalldataLength), executionCalldata, signature]
    function _validateSchedule(
        address account,
        bytes32 salt,
        bytes32 mode,
        bytes calldata data
    ) internal view override {
        uint16 executionCalldataLength = uint16(bytes2(data[0:2])); // First 2 bytes are the length
        bytes calldata executionCalldata = data[2:2 + executionCalldataLength]; // Next bytes are the calldata
        bytes calldata signature = data[2 + executionCalldataLength:]; // Remaining bytes are the signature
        require(_rawERC7579Validation(account, _getExecuteTypeHash(account, salt, mode, executionCalldata), signature));
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
