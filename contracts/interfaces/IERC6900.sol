// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

// TODO: Add & update comments

/// @dev A packed representation of a module function.
/// Consists of the following, left-aligned:
/// Module address: 20 bytes
/// Entity ID:      4 bytes
type ModuleEntity is bytes24;

/// @dev A packed representation of a validation function and its associated flags.
/// Consists of the following, left-aligned:
/// Module address:     20 bytes
/// Entity ID:          4 bytes
/// ValidationFlags:    1 byte
type ValidationConfig is bytes25;

// ValidationFlags layout:
// 0b00000___ // unused
// 0b_____A__ // isGlobal
// 0b______B_ // isSignatureValidation
// 0b_______C // isUserOpValidation
type ValidationFlags is uint8;

/// @dev A packed representation of a hook function and its associated flags.
/// Consists of the following, left-aligned:
/// Module address: 20 bytes
/// Entity ID:      4 bytes
/// Flags:          1 byte
///
/// Hook flags layout:
/// 0b00000___ // unused
/// 0b_____A__ // hasPre (exec only)
/// 0b______B_ // hasPost (exec only)
/// 0b_______C // hook type (0 for exec, 1 for validation)
type HookConfig is bytes25;

struct Call {
    // The target address for the account to call.
    address target;
    // The value to send with the call.
    uint256 value;
    // The calldata for the call.
    bytes data;
}
interface IERC6900ModularAccount {
    event ExecutionInstalled(address indexed module, ExecutionManifest manifest);
    event ExecutionUninstalled(address indexed module, bool onUninstallSucceeded, ExecutionManifest manifest);
    event ValidationInstalled(address indexed module, uint32 indexed entityId);
    event ValidationUninstalled(address indexed module, uint32 indexed entityId, bool onUninstallSucceeded);

    /// @notice Standard execute method.
    /// @param target The target address for the account to call.
    /// @param value The value to send with the call.
    /// @param data The calldata for the call.
    /// @return The return data from the call.
    function execute(address target, uint256 value, bytes calldata data) external payable returns (bytes memory);

    /// @notice Standard executeBatch method.
    /// @dev If the target is a module, the call SHOULD revert. If any of the calls revert, the entire batch MUST
    /// revert.
    /// @param calls The array of calls.
    /// @return An array containing the return data from the calls.
    function executeBatch(Call[] calldata calls) external payable returns (bytes[] memory);

    /// @notice Execute a call using the specified runtime validation.
    /// @param data The calldata to send to the account.
    /// @param authorization The authorization data to use for the call. The first 24 bytes is a ModuleEntity which
    /// specifies which runtime validation to use, and the rest is sent as a parameter to runtime validation.
    function executeWithRuntimeValidation(
        bytes calldata data,
        bytes calldata authorization
    ) external payable returns (bytes memory);

    /// @notice Install a module to the modular account.
    /// @param module The module to install.
    /// @param manifest the manifest describing functions to install.
    /// @param installData Optional data to be used by the account to handle the initial execution setup. Data encoding
    /// is implementation-specific.
    function installExecution(address module, ExecutionManifest calldata manifest, bytes calldata installData) external;

    /// @notice Uninstall a module from the modular account.
    /// @param module The module to uninstall.
    /// @param manifest The manifest describing functions to uninstall.
    /// @param uninstallData Optional data to be used by the account to handle the execution uninstallation. Data
    /// encoding is implementation-specific.
    function uninstallExecution(
        address module,
        ExecutionManifest calldata manifest,
        bytes calldata uninstallData
    ) external;

    /// @notice Installs a validation function across a set of execution selectors, and optionally mark it as a
    /// global validation function.
    /// @param validationConfig The validation function to install, along with configuration flags.
    /// @param selectors The selectors to install the validation function for.
    /// @param installData Optional data to be used by the account to handle the initial validation setup. Data
    /// encoding is implementation-specific.
    /// @param hooks Optional hooks to install and associate with the validation function. Data encoding is
    /// implementation-specific.
    function installValidation(
        ValidationConfig validationConfig,
        bytes4[] calldata selectors,
        bytes calldata installData,
        bytes[] calldata hooks
    ) external;

    /// @notice Uninstall a validation function from a set of execution selectors.
    /// @param validationFunction The validation function to uninstall.
    /// @param uninstallData Optional data to be used by the account to handle the validation uninstallation. Data
    /// encoding is implementation-specific.
    /// @param hookUninstallData Optional data to be used by the account to handle hook uninstallation. Data encoding
    /// is implementation-specific.
    function uninstallValidation(
        ModuleEntity validationFunction,
        bytes calldata uninstallData,
        bytes[] calldata hookUninstallData
    ) external;

    /// @notice Return a unique identifier for the account implementation.
    /// @dev This function MUST return a string in the format "vendor.account.semver". The vendor and account
    /// names MUST NOT contain a period character.
    /// @return The account ID.
    function accountId() external view returns (string memory);
}

struct ExecutionDataView {
    // The module that implements this execution function.
    // If this is a native function, the address must be the address of the account.
    address module;
    // Whether or not the function needs runtime validation, or can be called by anyone. The function can still be
    // state changing if this flag is set to true.
    // Note that even if this is set to true, user op validation will still be required, otherwise anyone could
    // drain the account of native tokens by wasting gas.
    bool skipRuntimeValidation;
    // Whether or not a global validation function may be used to validate this function.
    bool allowGlobalValidation;
    // The execution hooks for this function selector.
    HookConfig[] executionHooks;
}

struct ValidationDataView {
    // ValidationFlags layout:
    // 0b00000___ // unused
    // 0b_____A__ // isGlobal
    // 0b______B_ // isSignatureValidation
    // 0b_______C // isUserOpValidation
    ValidationFlags validationFlags;
    // The validation hooks for this validation function.
    HookConfig[] validationHooks;
    // Execution hooks to run with this validation function.
    HookConfig[] executionHooks;
    // The set of selectors that may be validated by this validation function.
    bytes4[] selectors;
}

interface IERC6900ModularAccountView {
    /// @notice Get the execution data for a selector.
    /// @dev If the selector is a native function, the module address will be the address of the account.
    /// @param selector The selector to get the data for.
    /// @return The execution data for this selector.
    function getExecutionData(bytes4 selector) external view returns (ExecutionDataView memory);

    /// @notice Get the validation data for a validation function.
    /// @dev If the selector is a native function, the module address will be the address of the account.
    /// @param validationFunction The validation function to get the data for.
    /// @return The validation data for this validation function.
    function getValidationData(ModuleEntity validationFunction) external view returns (ValidationDataView memory);
}

interface IERC6900Module is IERC165 {
    /// @notice Initialize module data for the modular account.
    /// @dev Called by the modular account during `installExecution`.
    /// @param data Optional bytes array to be decoded and used by the module to setup initial module data for the
    /// modular account.
    function onInstall(bytes calldata data) external;

    /// @notice Clear module data for the modular account.
    /// @dev Called by the modular account during `uninstallExecution`.
    /// @param data Optional bytes array to be decoded and used by the module to clear module data for the modular
    /// account.
    function onUninstall(bytes calldata data) external;

    /// @notice Return a unique identifier for the module.
    /// @dev This function MUST return a string in the format "vendor.module.semver". The vendor and module
    /// names MUST NOT contain a period character.
    /// @return The module ID.
    function moduleId() external view returns (string memory);
}

interface IERC6900ValidationModule is IERC6900Module {
    /// @notice Run the user operation validation function specified by the `entityId`.
    /// @param entityId An identifier that routes the call to different internal implementations, should there
    /// be more than one.
    /// @param userOp The user operation.
    /// @param userOpHash The user operation hash.
    /// @return Packed validation data for validAfter (6 bytes), validUntil (6 bytes), and authorizer (20 bytes).
    function validateUserOp(
        uint32 entityId,
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) external returns (uint256);

    /// @notice Run the runtime validation function specified by the `entityId`.
    /// @dev To indicate the entire call should revert, the function MUST revert.
    /// @param account The account to validate for.
    /// @param entityId An identifier that routes the call to different internal implementations, should there
    /// be more than one.
    /// @param sender The caller address.
    /// @param value The call value.
    /// @param data The calldata sent.
    /// @param authorization Additional data for the validation function to use.
    function validateRuntime(
        address account,
        uint32 entityId,
        address sender,
        uint256 value,
        bytes calldata data,
        bytes calldata authorization
    ) external;

    /// @notice Validates a signature using ERC-1271.
    /// @dev To indicate the entire call should revert, the function MUST revert.
    /// @param account The account to validate for.
    /// @param entityId An identifier that routes the call to different internal implementations, should there
    /// be more than one.
    /// @param sender The address that sent the ERC-1271 request to the smart account.
    /// @param hash The hash of the ERC-1271 request.
    /// @param signature The signature of the ERC-1271 request.
    /// @return The ERC-1271 `MAGIC_VALUE` if the signature is valid, or 0xFFFFFFFF if invalid.
    function validateSignature(
        address account,
        uint32 entityId,
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) external view returns (bytes4);
}

struct Execution {
    address target;
    uint256 value;
    bytes callData;
}

interface IERC6900ValidationHookModule is IERC6900Module {
    /// @notice Run the pre user operation validation hook specified by the `entityId`.
    /// @dev Pre user operation validation hooks MUST NOT return an authorizer value other than 0 or 1.
    /// @param entityId An identifier that routes the call to different internal implementations, should there
    /// be more than one.
    /// @param userOp The user operation.
    /// @param userOpHash The user operation hash.
    /// @return Packed validation data for validAfter (6 bytes), validUntil (6 bytes), and authorizer (20 bytes).
    function preUserOpValidationHook(
        uint32 entityId,
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) external returns (uint256);

    /// @notice Run the pre runtime validation hook specified by the `entityId`.
    /// @dev To indicate the entire call should revert, the function MUST revert.
    /// @param entityId An identifier that routes the call to different internal implementations, should there
    /// be more than one.
    /// @param sender The caller address.
    /// @param value The call value.
    /// @param data The calldata sent.
    /// @param authorization Additional data for the hook to use.
    function preRuntimeValidationHook(
        uint32 entityId,
        address sender,
        uint256 value,
        bytes calldata data,
        bytes calldata authorization
    ) external;

    /// @notice Run the pre signature validation hook specified by the `entityId`.
    /// @dev To indicate the call should revert, the function MUST revert.
    /// @param entityId An identifier that routes the call to different internal implementations, should there
    /// be more than one.
    /// @param sender The caller address.
    /// @param hash The hash of the message being signed.
    /// @param signature The signature of the message.
    function preSignatureValidationHook(
        uint32 entityId,
        address sender,
        bytes32 hash,
        bytes calldata signature
    ) external view;
}

struct ManifestExecutionFunction {
    // The selector to install.
    bytes4 executionSelector;
    // If true, the function won't need runtime validation, and can be called by anyone.
    bool skipRuntimeValidation;
    // If true, the function can be validated by a global validation function.
    bool allowGlobalValidation;
}

struct ManifestExecutionHook {
    bytes4 executionSelector;
    uint32 entityId;
    bool isPreHook;
    bool isPostHook;
}

/// @dev A struct describing how the module should be installed on a modular account.
struct ExecutionManifest {
    // Execution functions defined in this module to be installed on the MSCA.
    ManifestExecutionFunction[] executionFunctions;
    ManifestExecutionHook[] executionHooks;
    // List of ERC-165 interface IDs to add to account to support introspection checks. This MUST NOT include
    // IModule's interface ID.
    bytes4[] interfaceIds;
}

interface IERC6900ExecutionModule is IERC6900Module {
    /// @notice Describe the contents and intended configuration of the module.
    /// @dev This manifest MUST stay constant over time.
    /// @return A manifest describing the contents and intended configuration of the module.
    function executionManifest() external pure returns (ExecutionManifest memory);
}

interface IERC6900ExecutionHookModule is IERC6900Module {
    /// @notice Run the pre execution hook specified by the `entityId`.
    /// @dev To indicate the entire call should revert, the function MUST revert.
    /// @param entityId An identifier that routes the call to different internal implementations, should there
    /// be more than one.
    /// @param sender The caller address.
    /// @param value The call value.
    /// @param data The calldata sent. For `executeUserOp` calls of validation-associated hooks, hook modules
    /// should receive the full calldata.
    /// @return Context to pass to a post execution hook, if present. An empty bytes array MAY be returned.
    function preExecutionHook(
        uint32 entityId,
        address sender,
        uint256 value,
        bytes calldata data
    ) external returns (bytes memory);

    /// @notice Run the post execution hook specified by the `entityId`.
    /// @dev To indicate the entire call should revert, the function MUST revert.
    /// @param entityId An identifier that routes the call to different internal implementations, should there
    /// be more than one.
    /// @param preExecHookData The context returned by its associated pre execution hook.
    function postExecutionHook(uint32 entityId, bytes calldata preExecHookData) external;
}
