// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ValidationConfig, ModuleEntity, ValidationFlags, HookConfig, ExecutionManifest, ManifestExecutionHook, ManifestExecutionFunction, Call} from "../../interfaces/IERC6900.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {Packing} from "@openzeppelin/contracts/utils/Packing.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @dev Library with common ERC-6900 utility functions.
 *
 * See https://eips.ethereum.org/EIPS/eip-6900[ERC-6900].
 */
// slither-disable-next-line unused-state
library ERC6900Utils {
    using Packing for *;

    error ERC6900ModuleInterfaceNotSupported(address module, bytes4 expectedInterface);
    error ERC6900AlreadySetSelectorForValidation(ModuleEntity validationFunction, bytes4 selector);
    error ERC6900AlreadySetValidationHookForValidation();
    error ERC6900AlreadySetExecutionHookForExecution();
    error ERC6900AlreadySetExecutionHookForValidation();
    error ERC6900AlreadyUsedModuleFunctionExecutionSelector(bytes4 selector);
    error ERC6900ExecutionSelectorConflictingWithERC4337Function(address module, bytes4 selector);
    error ERC6900ExecutionSelectorConflictingWithERC6900Function(address module, bytes4 selector);
    error ERC6900BadUserOpValidation(ModuleEntity moduleEntity);
    error ERC6900BadSignatureValidation(ModuleEntity moduleEntity);
    error ERC6900MissingValidationForSelector(bytes4 selector);
    error ERC6900ExecutionSelectorNotAllowedForGlobalValidation(
        ModuleEntity validationModuleEntity,
        bytes4 executionSelector
    );
    error ERC6900InvalidExecuteTarget();
    error ERC6900ExecutionFailed(address target, uint256 value, bytes data);

    // ModuleEntity

    function unpack(ModuleEntity moduleEntity) internal pure returns (address, uint32) {
        return (module(moduleEntity), entityId(moduleEntity));
    }

    function module(ModuleEntity moduleEntity) internal pure returns (address) {
        return address(Packing.extract_32_20(ModuleEntity.unwrap(moduleEntity), 0));
    }

    function entityId(ModuleEntity moduleEntity) internal pure returns (uint32) {
        return uint32(Packing.extract_32_4(ModuleEntity.unwrap(moduleEntity), 20));
    }

    // ValidationFlags

    function isGlobalValidation(ValidationFlags validationFlags) internal pure returns (bool) {
        return ValidationFlags.unwrap(validationFlags) & uint8(0x04) == 0x04; // 0b00000100
    }

    function isSignatureValidation(ValidationFlags validationFlags) internal pure returns (bool) {
        return ValidationFlags.unwrap(validationFlags) & uint8(0x02) == 0x02; // 0b00000010
    }

    function isUserOpValidation(ValidationFlags validationFlags) internal pure returns (bool) {
        return ValidationFlags.unwrap(validationFlags) & uint8(0x01) == 0x01; // 0b00000001
    }

    // ValidationConfig

    // function module(ValidationConfig validationConfig) internal pure returns (address) {
    //     return address(Packing.extract_32_20(ValidationConfig.unwrap(validationConfig), 0));
    // }

    // function module(bytes calldata hook) internal pure returns (address) {
    //     return address(Packing.extract_32_20(bytes32(hook), 0));
    // }

    // function entityId(ValidationConfig validationConfig) internal pure returns (uint32) {
    //     return uint32(Packing.extract_32_4(ValidationConfig.unwrap(validationConfig), 20));
    // }

    function unpack(ValidationConfig validationConfig) internal pure returns (ModuleEntity, ValidationFlags) {
        return (
            ModuleEntity.wrap(Packing.extract_32_24(ValidationConfig.unwrap(validationConfig), 0)),
            ValidationFlags.wrap(uint8(Packing.extract_32_1(ValidationConfig.unwrap(validationConfig), 21)))
        );
    }

    // function moduleEntity(ValidationConfig validationConfig) internal pure returns (ModuleEntity) {
    //     return ModuleEntity.wrap(Packing.extract_32_24(ValidationConfig.unwrap(validationConfig), 0));
    // }

    // function getValidationFlags(ValidationConfig validationConfig) internal pure returns (ValidationFlags) {
    //     return ValidationFlags.wrap(uint8(Packing.extract_32_1(ValidationConfig.unwrap(validationConfig), 21)));
    // }

    // HookConfig

    function extractHookConfig(bytes calldata hook) internal pure returns (HookConfig) {
        return HookConfig.wrap(bytes25(hook[:25]));
    }

    function isValidationHook(HookConfig hookConfig) internal pure returns (bool) {
        return uint8(Packing.extract_32_1(HookConfig.unwrap(hookConfig), 24) & bytes1(0x01)) == 1;
    }

    function module(HookConfig hookConfig) internal pure returns (address) {
        return address(Packing.extract_32_20(HookConfig.unwrap(hookConfig), 0));
    }

    function entity(HookConfig hookConfig) internal pure returns (uint32) {
        return uint32(Packing.extract_32_4(HookConfig.unwrap(hookConfig), 20));
    }

    function getHookData(bytes calldata hook) internal pure returns (bytes calldata) {
        return hook[:25];
    }

    // function pack(
    //     address module,
    //     uint32 entityId,
    //     bool isPreHook,
    //     bool isPostHook
    // ) internal pure returns (bytes calldata) {
    //     return hook[:25];
    // }
}
