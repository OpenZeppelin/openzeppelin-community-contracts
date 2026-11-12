// contracts/MyERC7579SocialRecovery.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ERC7579ExecutorUpgradeable} from "../../../../account/modules/ERC7579ExecutorUpgradeable.sol";
import {ERC7579ValidatorUpgradeable} from "../../../../account/modules/ERC7579ValidatorUpgradeable.sol";
import {ERC7579MultisigUpgradeable} from "../../../../account/modules/ERC7579MultisigUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

abstract contract MyERC7579SocialRecoveryUpgradeable is Initializable, EIP712Upgradeable, ERC7579ExecutorUpgradeable, ERC7579MultisigUpgradeable, NoncesUpgradeable {
    bytes32 private constant RECOVER_TYPEHASH =
        keccak256("Recover(address account,bytes32 salt,uint256 nonce,bytes32 mode,bytes executionCalldata)");

    function __MyERC7579SocialRecovery_init() internal onlyInitializing {
    }

    function __MyERC7579SocialRecovery_init_unchained() internal onlyInitializing {
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
    ) internal override returns (bytes calldata) {
        uint16 executionCalldataLength = uint16(bytes2(data[0:2])); // First 2 bytes are the length
        bytes calldata executionCalldata = data[2:2 + executionCalldataLength]; // Next bytes are the calldata
        bytes calldata signature = data[2 + executionCalldataLength:]; // Remaining bytes are the signature
        require(_rawERC7579Validation(account, _getExecuteTypeHash(account, salt, mode, executionCalldata), signature));
        return executionCalldata;
    }

    function _getExecuteTypeHash(
        address account,
        bytes32 salt,
        bytes32 mode,
        bytes calldata executionCalldata
    ) internal returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(abi.encode(RECOVER_TYPEHASH, account, salt, _useNonce(account), mode, executionCalldata))
            );
    }
}
