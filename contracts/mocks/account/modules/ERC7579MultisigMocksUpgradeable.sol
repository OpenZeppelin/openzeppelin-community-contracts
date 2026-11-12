// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ERC7579ExecutorUpgradeable} from "../../../account/modules/ERC7579ExecutorUpgradeable.sol";
import {ERC7579ValidatorUpgradeable} from "../../../account/modules/ERC7579ValidatorUpgradeable.sol";
import {ERC7579MultisigUpgradeable} from "../../../account/modules/ERC7579MultisigUpgradeable.sol";
import {ERC7579MultisigWeightedUpgradeable} from "../../../account/modules/ERC7579MultisigWeightedUpgradeable.sol";
import {ERC7579MultisigConfirmationUpgradeable} from "../../../account/modules/ERC7579MultisigConfirmationUpgradeable.sol";
import {ERC7579MultisigStorageUpgradeable} from "../../../account/modules/ERC7579MultisigStorageUpgradeable.sol";
import {MODULE_TYPE_EXECUTOR, IERC7579Hook} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {Mode} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract ERC7579MultisigExecutorMockUpgradeable is Initializable, EIP712Upgradeable, ERC7579ExecutorUpgradeable, ERC7579MultisigUpgradeable {
    bytes32 private constant EXECUTE_OPERATION =
        keccak256("ExecuteOperation(address account,bytes32 mode,bytes executionCalldata,bytes32 salt)");

    function __ERC7579MultisigExecutorMock_init() internal onlyInitializing {
    }

    function __ERC7579MultisigExecutorMock_init_unchained() internal onlyInitializing {
    }
    function isModuleType(uint256 moduleTypeId) public pure override(ERC7579ExecutorUpgradeable, ERC7579ValidatorUpgradeable) returns (bool) {
        return ERC7579ExecutorUpgradeable.isModuleType(moduleTypeId) || ERC7579ExecutorUpgradeable.isModuleType(moduleTypeId);
    }

    // Data encoding: [uint16(executionCalldataLength), executionCalldata, signature]
    function _validateExecution(
        address account,
        bytes32 salt,
        bytes32 mode,
        bytes calldata data
    ) internal view override returns (bytes calldata) {
        uint16 executionCalldataLength = uint16(bytes2(data[0:2])); // First 2 bytes are the length
        bytes calldata executionCalldata = data[2:2 + executionCalldataLength]; // Next bytes are the calldata
        bytes32 typeHash = _getExecuteTypeHash(account, salt, mode, executionCalldata);
        require(_rawERC7579Validation(account, typeHash, data[2 + executionCalldataLength:])); // Remaining bytes are the signature
        return executionCalldata;
    }

    function _getExecuteTypeHash(
        address account,
        bytes32 salt,
        bytes32 mode,
        bytes calldata executionCalldata
    ) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(EXECUTE_OPERATION, account, salt, mode, executionCalldata)));
    }
}

abstract contract ERC7579MultisigWeightedExecutorMockUpgradeable is Initializable, EIP712Upgradeable, ERC7579ExecutorUpgradeable, ERC7579MultisigWeightedUpgradeable {
    bytes32 private constant EXECUTE_OPERATION =
        keccak256("ExecuteOperation(address account,bytes32 mode,bytes executionCalldata,bytes32 salt)");

    function __ERC7579MultisigWeightedExecutorMock_init() internal onlyInitializing {
    }

    function __ERC7579MultisigWeightedExecutorMock_init_unchained() internal onlyInitializing {
    }
    function isModuleType(uint256 moduleTypeId) public pure override(ERC7579ExecutorUpgradeable, ERC7579ValidatorUpgradeable) returns (bool) {
        return ERC7579ExecutorUpgradeable.isModuleType(moduleTypeId) || ERC7579ExecutorUpgradeable.isModuleType(moduleTypeId);
    }

    // Data encoding: [uint16(executionCalldataLength), executionCalldata, signature]
    function _validateExecution(
        address account,
        bytes32 salt,
        bytes32 mode,
        bytes calldata data
    ) internal view override returns (bytes calldata) {
        uint16 executionCalldataLength = uint16(bytes2(data[0:2])); // First 2 bytes are the length
        bytes calldata executionCalldata = data[2:2 + executionCalldataLength]; // Next bytes are the calldata
        bytes32 typeHash = _getExecuteTypeHash(account, salt, mode, executionCalldata);
        require(_rawERC7579Validation(account, typeHash, data[2 + executionCalldataLength:])); // Remaining bytes are the signature
        return executionCalldata;
    }

    function _getExecuteTypeHash(
        address account,
        bytes32 salt,
        bytes32 mode,
        bytes calldata executionCalldata
    ) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(EXECUTE_OPERATION, account, salt, mode, executionCalldata)));
    }
}

abstract contract ERC7579MultisigConfirmationExecutorMockUpgradeable is Initializable, ERC7579ExecutorUpgradeable, ERC7579MultisigConfirmationUpgradeable {
    bytes32 private constant EXECUTE_OPERATION =
        keccak256("ExecuteOperation(address account,bytes32 mode,bytes executionCalldata,bytes32 salt)");

    function __ERC7579MultisigConfirmationExecutorMock_init() internal onlyInitializing {
    }

    function __ERC7579MultisigConfirmationExecutorMock_init_unchained() internal onlyInitializing {
    }
    function isModuleType(uint256 moduleTypeId) public pure override(ERC7579ExecutorUpgradeable, ERC7579ValidatorUpgradeable) returns (bool) {
        return ERC7579ExecutorUpgradeable.isModuleType(moduleTypeId) || ERC7579ExecutorUpgradeable.isModuleType(moduleTypeId);
    }

    // Data encoding: [uint16(executionCalldataLength), executionCalldata, signature]
    function _validateExecution(
        address account,
        bytes32 salt,
        bytes32 mode,
        bytes calldata data
    ) internal view override returns (bytes calldata) {
        uint16 executionCalldataLength = uint16(bytes2(data[0:2])); // First 2 bytes are the length
        bytes calldata executionCalldata = data[2:2 + executionCalldataLength]; // Next bytes are the calldata
        bytes32 typeHash = _getExecuteTypeHash(account, salt, mode, executionCalldata);
        require(_rawERC7579Validation(account, typeHash, data[2 + executionCalldataLength:])); // Remaining bytes are the signature
        return executionCalldata;
    }

    function _getExecuteTypeHash(
        address account,
        bytes32 salt,
        bytes32 mode,
        bytes calldata executionCalldata
    ) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(EXECUTE_OPERATION, account, salt, mode, executionCalldata)));
    }
}

abstract contract ERC7579MultisigStorageExecutorMockUpgradeable is Initializable, EIP712Upgradeable, ERC7579ExecutorUpgradeable, ERC7579MultisigStorageUpgradeable {
    bytes32 private constant EXECUTE_OPERATION =
        keccak256("ExecuteOperation(address account,bytes32 mode,bytes executionCalldata,bytes32 salt)");

    function __ERC7579MultisigStorageExecutorMock_init() internal onlyInitializing {
    }

    function __ERC7579MultisigStorageExecutorMock_init_unchained() internal onlyInitializing {
    }
    function isModuleType(uint256 moduleTypeId) public pure override(ERC7579ExecutorUpgradeable, ERC7579ValidatorUpgradeable) returns (bool) {
        return ERC7579ExecutorUpgradeable.isModuleType(moduleTypeId) || ERC7579ExecutorUpgradeable.isModuleType(moduleTypeId);
    }

    // Data encoding: [uint16(executionCalldataLength), executionCalldata, signature]
    function _validateExecution(
        address account,
        bytes32 salt,
        bytes32 mode,
        bytes calldata data
    ) internal view override returns (bytes calldata) {
        uint16 executionCalldataLength = uint16(bytes2(data[0:2])); // First 2 bytes are the length
        bytes calldata executionCalldata = data[2:2 + executionCalldataLength]; // Next bytes are the calldata
        bytes32 typeHash = _getExecuteTypeHash(account, salt, mode, executionCalldata);
        require(_rawERC7579Validation(account, typeHash, data[2 + executionCalldataLength:])); // Remaining bytes are the signature
        return executionCalldata;
    }

    function _getExecuteTypeHash(
        address account,
        bytes32 salt,
        bytes32 mode,
        bytes calldata executionCalldata
    ) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(EXECUTE_OPERATION, account, salt, mode, executionCalldata)));
    }
}
