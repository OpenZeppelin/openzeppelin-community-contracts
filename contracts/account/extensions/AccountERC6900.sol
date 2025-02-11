// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {PackedUserOperation, IAccount} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {Packing} from "@openzeppelin/contracts/utils/Packing.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Calldata} from "@openzeppelin/contracts/utils/Calldata.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC6900ModularAccount, IERC6900Module, IERC6900ValidationModule, IERC6900ExecutionModule, ValidationConfig, ModuleEntity, ValidationFlags, HookConfig, ExecutionManifest, ManifestExecutionHook, ManifestExecutionFunction, Call} from "../../interfaces/IERC6900.sol";
import {ERC6900Utils} from "../utils/ERC6900Utils.sol";
import {ERC7739} from "../../utils/cryptography/ERC7739.sol";
import {AccountCore} from "../AccountCore.sol";

/**
 * @dev Extension of {AccountCore} that implements support for ERC-6900 modules.
 *
 * To comply with the ERC-1271 support requirement, this contract implements {ERC7739} as an
 * opinionated layer to avoid signature replayability across accounts controlled by the same key.
 *
 * This contract does not implement validation logic for user operations since these functionality
 * is often delegated to self-contained validation modules. Developers must install a validator module
 * upon initialization (or any other mechanism to enable execution from the account):
 *
 * ```solidity
 * contract MyAccountERC6900is AccountERC6900, Initializable {
 *     constructor() EIP712("MyAccount", "1") {}
 *
 *   function installValidation(
 *       ValidationConfig validationConfig,
 *       bytes4[] calldata selectors,
 *       bytes calldata installData,
 *       bytes[] calldata hooks
 *   ) public initializer {
 *     _installValidation(validationConfig, selectors, installData, hooks);
 *   }
 * }
 * ```
 *
 */

abstract contract AccountERC6900 is AccountCore, ERC7739, IERC6900ModularAccount {
    using Bytes for *;
    using ERC6900Utils for *;
    using EnumerableSet for *;
    using Packing for bytes32;

    mapping(ModuleEntity moduleEntity => Validation) private _validations;
    mapping(bytes4 selector => Execution) private _executions;
    mapping(bytes4 interfaceId => bool supported) private _interfaceIds;
    mapping(bytes4 selector => address) private _fallbacks;

    struct Validation {
        EnumerableSet.Bytes32Set selectors;
        ValidationFlags validationFlags;
        EnumerableSet.Bytes32Set validationHooks;
        EnumerableSet.Bytes32Set executionHooks;
    }

    struct Execution {
        address module;
        bool skipRuntimeValidation;
        bool allowGlobalValidation;
        EnumerableSet.Bytes32Set executionHooks;
    }

    /// @dev See {_fallback}.
    fallback(bytes calldata) external payable virtual returns (bytes memory) {
        return _fallback();
    }

    /// @inheritdoc IERC6900ModularAccount
    function accountId() public view virtual returns (string memory) {
        // vendorname.accountname.semver
        return "@openzeppelin/community-contracts.AccountERC6900.v0.0.0";
    }

    /// @inheritdoc IERC6900ModularAccount
    function installValidation(
        ValidationConfig validationConfig,
        bytes4[] calldata selectors,
        bytes calldata installData,
        bytes[] calldata hooks
    ) public virtual onlyEntryPointOrSelf {
        _installValidation(validationConfig, selectors, installData, hooks);
    }

    /// @inheritdoc IERC6900ModularAccount
    function uninstallValidation(
        ModuleEntity validationFunction,
        bytes calldata uninstallData,
        bytes[] calldata hookUninstallData
    ) public virtual onlyEntryPointOrSelf {
        // _uninstallModule(moduleTypeId, module, deInitData);
    }

    /// @inheritdoc IERC6900ModularAccount
    function installExecution(
        address module,
        ExecutionManifest memory manifest,
        bytes calldata installData
    ) public virtual onlyEntryPointOrSelf {
        _installExecution(module, manifest, installData);
    }

    /// @inheritdoc IERC6900ModularAccount
    function uninstallExecution(
        address module,
        ExecutionManifest calldata manifest,
        bytes calldata uninstallData
    ) public virtual onlyEntryPointOrSelf {
        // _uninstallModule(moduleTypeId, module, deInitData);
    }

    /// @inheritdoc IERC6900ModularAccount
    function execute(
        address target,
        uint256 value,
        bytes calldata data
    ) public payable virtual onlyEntryPointOrSelf returns (bytes memory) {
        return _execute(target, value, data);
    }

    /// @inheritdoc IERC6900ModularAccount
    function executeBatch(Call[] calldata calls) public payable virtual onlyEntryPointOrSelf returns (bytes[] memory) {
        bytes[] memory returnedData = new bytes[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            returnedData[i] = _execute(calls[i].target, calls[i].value, calls[i].data);
        }
        return returnedData;
    }

    /// @inheritdoc IERC6900ModularAccount
    function executeWithRuntimeValidation(
        bytes calldata data,
        bytes calldata authorization
    ) public payable virtual onlyEntryPointOrSelf returns (bytes memory) {
        ModuleEntity validationModuleEntity = ModuleEntity.wrap(bytes24(authorization[:24]));
        bytes calldata validationAuth = authorization[24:];
        IERC6900ValidationModule(validationModuleEntity.module()).validateRuntime(
            address(this),
            validationModuleEntity.entityId(),
            msg.sender,
            msg.value,
            data,
            validationAuth
        );
        return _execute(address(this), msg.value, data);
    }

    /**
     * @dev Validates a user operation with {_signableUserOpHash} and returns the validation data
     * if the module specified by the first 20 bytes of the nonce key is installed. Falls back to
     * {AccountCore-_validateUserOp} otherwise.
     *
     * See {_extractUserOpValidator} for the module extraction logic.
     */
    function _validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal virtual override returns (uint256) {
        ModuleEntity validationModuleEntity = _extractUserOpValidator(userOp);
        (address module, uint32 entityId) = validationModuleEntity.unpack();
        Validation storage validation = _validations[validationModuleEntity];
        ValidationFlags _validationFlags = validation.validationFlags;
        // If a validation function is attempted to be used for user op validation
        // and the flag isUserOpValidation is set to false, validation MUST revert
        require(
            !_validationFlags.isUserOpValidation(),
            ERC6900Utils.ERC6900BadUserOpValidation(validationModuleEntity)
        );
        bytes4 executionSelector = bytes4(userOp.callData[:4]);
        // validation installation MAY specify the isGlobal flag as true
        if (_validationFlags.isGlobalValidation()) {
            Execution storage execution = _executions[executionSelector];
            // The account MUST consider the validation applicable to any module
            // execution function with the allowGlobalValidation flag set to true
            require(
                !execution.allowGlobalValidation,
                ERC6900Utils.ERC6900ExecutionSelectorNotAllowedForGlobalValidation(
                    validationModuleEntity,
                    executionSelector
                )
            );
        } else {
            // validation functions have a configurable range of applicability.
            // This can be configured with selectors installed to a validation
            require(
                !validation.selectors.contains(executionSelector),
                ERC6900Utils.ERC6900MissingValidationForSelector(executionSelector)
            );
        }
        // If the selector being checked is execute or executeBatch,
        // it MUST perform additional checking on target.
        if (executionSelector == IERC6900ModularAccount.execute.selector) {
            (address target, , ) = abi.decode(userOp.callData[4:], (address, uint256, bytes));
            require(target != address(this), ERC6900Utils.ERC6900InvalidExecuteTarget());
        }
        if (executionSelector == IERC6900ModularAccount.executeBatch.selector) {
            Call[] memory calls = abi.decode(userOp.callData[4:], (Call[]));
            for (uint256 i = 0; i < calls.length; i++) {
                require(calls[i].target != address(this), ERC6900Utils.ERC6900InvalidExecuteTarget());
            }
        }
        return
            IERC6900ValidationModule(module).validateUserOp(entityId, userOp, _signableUserOpHash(userOp, userOpHash));
    }

    /**
     * @dev Lowest-level signature validation function. See {ERC7739-_rawSignatureValidation}.
     *
     * This function delegates the signature validation to a validation module if the first 20 bytes of the
     * signature correspond to an installed validator module.
     *
     * See {_extractSignatureValidator} for the module extraction logic.
     */
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        if (signature.length < 25) return false;
        (ModuleEntity validationModuleEntity, bytes calldata innerSignature) = _extractSignatureValidator(signature);
        (address module, uint32 entityId) = validationModuleEntity.unpack();
        // If the validation function is attempted to be used for signature validation
        // and the flag isSignatureValidation is set to false, validation MUST revert
        require(
            !_validations[validationModuleEntity].validationFlags.isSignatureValidation(),
            ERC6900Utils.ERC6900BadSignatureValidation(validationModuleEntity)
        );

        return
            IERC6900ValidationModule(module).validateSignature(
                address(this),
                entityId,
                msg.sender,
                hash,
                innerSignature
            ) == IERC1271.isValidSignature.selector;
    }

    /**
     * @dev ERC-6900 execution logic.
     *
     * Reverts if the call type is not supported.
     */
    function _execute(address target, uint256 value, bytes calldata data) internal virtual returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{value: value}(data);

        require(success, ERC6900Utils.ERC6900ExecutionFailed(target, value, data));
        return returndata;
    }

    /**
     * @dev Installs a validation module of the given type with the given initialization data.
     *
     *
     * Requirements:
     *
     * * TODO
     *
     * Emits a {ValidationInstalled} event.
     */
    function _installValidation(
        ValidationConfig validationConfig,
        bytes4[] calldata selectors,
        bytes calldata installData,
        bytes[] calldata hooks
    ) internal virtual {
        (ModuleEntity moduleEntity, ValidationFlags _validationFlags) = validationConfig.unpack();
        (address module, uint32 entityId) = moduleEntity.unpack();
        // Modules MUST implement ERC-165 for IModule.
        require(
            ERC165Checker.supportsInterface(module, type(IERC6900Module).interfaceId),
            ERC6900Utils.ERC6900ModuleInterfaceNotSupported(module, type(IERC6900Module).interfaceId)
        );
        Validation storage validation = _validations[moduleEntity];
        // The account MUST configure the validation function to validate all of the selectors specified by the user.
        for (uint256 i = 0; i < selectors.length; i++) {
            require(
                validation.selectors.add(selectors[i]),
                ERC6900Utils.ERC6900AlreadySetSelectorForValidation(moduleEntity, selectors[i])
            );
        }
        // - The account MUST install all validation hooks specified by the user and SHOULD call onInstall
        // with the user-provided data on the hook module to initialize state if specified by the user.
        // - The account MUST install all execution hooks specified by the user and SHOULD call onInstall
        // with the user-provided data on the hook module to initialize state if specified by the user.
        for (uint256 i = 0; i < hooks.length; i++) {
            bytes calldata hook = hooks[i];
            HookConfig hookConfig = hook.extractHookConfig();
            address hookModule = hookConfig.module();
            bytes4 expectedInterface;
            if (hookConfig.isValidationHook()) {
                expectedInterface = type(IERC6900ValidationModule).interfaceId;
                require(
                    validation.validationHooks.add(bytes32(hook[:24])),
                    ERC6900Utils.ERC6900AlreadySetValidationHookForValidation()
                );
            } else {
                // Is execution hook
                expectedInterface = type(IERC6900ExecutionModule).interfaceId;
                require(
                    validation.executionHooks.add(bytes32(hook[:25])),
                    ERC6900Utils.ERC6900AlreadySetExecutionHookForValidation()
                );
            }
            // TODO: Firstly check interface is supported
            if (hookModule.code.length > 0) {
                require(
                    ERC165Checker.supportsInterface(hookModule, expectedInterface),
                    ERC6900Utils.ERC6900ModuleInterfaceNotSupported(hookModule, expectedInterface)
                );
                //IERC6900Module(hookModule).onInstall(installData); //TODO Enable
            }
        }
        // The account MUST set all flags as specified, like isGlobal, isSignatureValidation, and isUserOpValidation.
        validation.validationFlags = _validationFlags;
        // The account SHOULD call onInstall on the validation module to initialize state if specified by the user.
        IERC6900Module(module).onInstall(installData);
        // The account MUST emit ValidationInstalled as defined in the interface for all installed validation functions.
        emit ValidationInstalled(module, entityId);
    }

    function _installExecution(
        address module,
        ExecutionManifest memory manifest, // TODO: change to call data
        bytes calldata installData
    ) internal virtual {
        // Modules MUST implement ERC-165 for IModule.
        require(
            IERC6900Module(module).supportsInterface(type(IERC6900Module).interfaceId), //TODO Use checker
            ERC6900Utils.ERC6900ModuleInterfaceNotSupported(module, type(IERC6900Module).interfaceId)
        );
        // The account MUST install all execution functions and set flags and fields as specified in the manifest.
        ManifestExecutionFunction[] memory executionFunctions = manifest.executionFunctions;
        for (uint256 i = 0; i < executionFunctions.length; i++) {
            ManifestExecutionFunction memory executionFunction = executionFunctions[i];
            bytes4 executionSelector = executionFunction.executionSelector;
            Execution storage execution = _executions[executionSelector];
            // An execution function selector MUST be unique in the account.
            require(
                execution.module == address(0),
                ERC6900Utils.ERC6900AlreadyUsedModuleFunctionExecutionSelector(executionSelector)
            );
            // An execution function selector MUST not conflict with native ERC-4337 and ERC-6900 functions.
            require(
                IAccount.validateUserOp.selector != executionSelector, // TODO Check other ERC-4337 functions
                ERC6900Utils.ERC6900ExecutionSelectorConflictingWithERC4337Function(module, executionSelector)
            );
            require(
                IERC6900ModularAccount.execute.selector != executionSelector, // TODO Check other ERC-6900 functions
                ERC6900Utils.ERC6900ExecutionSelectorConflictingWithERC6900Function(module, executionSelector)
            );
            execution.module = module;
            execution.skipRuntimeValidation = executionFunction.skipRuntimeValidation;
            execution.allowGlobalValidation = executionFunction.allowGlobalValidation;
        }
        // The account MUST add all execution hooks as specified in the manifest.
        ManifestExecutionHook[] memory executionHooks = manifest.executionHooks;
        for (uint256 i = 0; i < executionHooks.length; i++) {
            ManifestExecutionHook memory executionHook = executionHooks[i];
            bytes4 executionSelector = executionHook.executionSelector;
            // module
            uint32 entityId = executionHook.entityId;
            bool isPreHook = executionHook.isPreHook;
            bool isPostHook = executionHook.isPostHook;
            Execution storage execution = _executions[executionSelector];
            require(
                execution.executionHooks.add(bytes32(abi.encodePacked(module, entityId, isPreHook, isPostHook))),
                ERC6900Utils.ERC6900AlreadySetExecutionHookForExecution()
            );
        }
        // The account SHOULD add all supported interfaces as specified in the manifest.
        bytes4[] memory interfaceIds = manifest.interfaceIds;
        for (uint256 i = 0; i < interfaceIds.length; i++) {
            bytes4 interfaceId = interfaceIds[i];
            require(!_interfaceIds[interfaceId], "Interface already set"); // TODO use custom error
            _interfaceIds[interfaceId] = true;
        }
        // The account SHOULD call onInstall on the execution module to initialize state if specified by the user.
        IERC6900Module(module).onInstall(installData);
        // The account MUST emit ExecutionInstalled as defined in the interface for all installed executions.
        emit ExecutionInstalled(module, manifest);
    }

    /**
     * @dev Uninstalls a module.
     *
     *
     * Requirements:
     *
     * * TODO
     */
    function _uninstallModule(uint256 moduleTypeId, address module, bytes memory deInitData) internal virtual {
        // TODO
        // IERC6900Module(module).onUninstall(deInitData);
        // emit ModuleUninstalled(moduleTypeId, module);
    }

    /**
     * @dev Fallback function that delegates the call to the installed handler for the given selector.
     *
     */
    function _fallback() internal virtual returns (bytes memory) {
        // TODO
    }

    /// @dev Returns the fallback handler for the given selector. Returns `address(0)` if not installed.
    function _fallbackHandler(bytes4 selector) internal view virtual returns (address) {
        return _fallbacks[selector];
    }

    function _decodeValidationConfig(
        ValidationConfig validationConfig
    ) internal pure virtual returns (address module, uint32 entityId, bytes1 validationFlags) {
        return (
            address(Packing.extract_32_20(ValidationConfig.unwrap(validationConfig), 0)),
            uint32(Packing.extract_32_4(ValidationConfig.unwrap(validationConfig), 20)),
            Packing.extract_32_1(ValidationConfig.unwrap(validationConfig), 21)
        );
    }

    /**
     * @dev Extracts the validator from the user operation.
     *
     */
    function _extractUserOpValidator(PackedUserOperation calldata userOp) internal pure virtual returns (ModuleEntity) {
        return ModuleEntity.wrap(bytes24(userOp.signature[:24]));
    }

    /**
     * @dev Extracts the validator from the signature.
     *
     * To construct a signature, set the first 20 bytes as the module address, the next 4 bytes
     * as the entityId and the remaining bytes as the signature data:
     *
     * ```
     * <module address (20 bytes)> | <entity ID (4 bytes)> | <signature data>
     * ```
     */
    function _extractSignatureValidator(
        bytes calldata signature
    ) internal pure virtual returns (ModuleEntity moduleEntity, bytes calldata innerSignature) {
        return (ModuleEntity.wrap(bytes24(signature[0:24])), signature[24:]);
    }

    /**
     * @dev Extract the function selector from initData/deInitData for MODULE_TYPE_FALLBACK
     *
     * NOTE: If we had calldata here, we would could use calldata slice which are cheaper to manipulate and don't
     * require actual copy. However, this would require `_installModule` to get a calldata bytes object instead of a
     * memory bytes object. This would prevent calling `_installModule` from a contract constructor and would force
     * the use of external initializers. That may change in the future, as most accounts will probably be deployed as
     * clones/proxy/ERC-7702 delegates and therefore rely on initializers anyway.
     */
    function _decodeFallbackData(
        bytes memory data
    ) internal pure virtual returns (bytes4 selector, bytes memory remaining) {
        return (bytes4(data), data.slice(4));
    }

    // TODO: Remove flat function and update test
    function installExecutionFlat(
        address module,
        bytes4 executionSelector,
        // TODO: Add exec flags
        bytes4 executionHookSelector,
        uint32 executionHookEntityId,
        // TODO: Add exec hook flags
        bytes4[] memory manifestInterfaceIds,
        bytes calldata installData
    ) public virtual onlyEntryPointOrSelf {
        ExecutionManifest memory manifest = ExecutionManifest({
            executionFunctions: new ManifestExecutionFunction[](1),
            executionHooks: new ManifestExecutionHook[](1),
            interfaceIds: manifestInterfaceIds
        });
        manifest.executionFunctions[0] = ManifestExecutionFunction({
            executionSelector: executionSelector,
            skipRuntimeValidation: true,
            allowGlobalValidation: true
        });
        manifest.executionHooks[0] = ManifestExecutionHook({
            executionSelector: executionHookSelector,
            entityId: executionHookEntityId,
            isPreHook: true,
            isPostHook: true
        });

        installExecution(module, manifest, installData);
    }
}
