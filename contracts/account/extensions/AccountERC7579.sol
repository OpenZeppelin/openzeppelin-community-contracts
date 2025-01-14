// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC7579Module, IERC7579Validator, IERC7579Execution, IERC7579AccountConfig, IERC7579ModuleConfig, MODULE_TYPE_VALIDATOR, MODULE_TYPE_EXECUTOR, MODULE_TYPE_FALLBACK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {ERC7579Utils, Mode, CallType, ExecType} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {Packing} from "@openzeppelin/contracts/utils/Packing.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Calldata} from "@openzeppelin/contracts/utils/Calldata.sol";
import {ERC7739} from "../../utils/cryptography/ERC7739.sol";
import {AccountCore} from "../AccountCore.sol";

/**
 * @dev Extension of {AccountCore} that implements support for ERC-7579 modules.
 *
 * To comply with the ERC-1271 support requirement, this contract implements {ERC7739} as an
 * opinionated layer to avoid signature replayability across accounts controlled by the same key.
 *
 * This contract does not implement validation logic for user operations since these functionality
 * is often delegated to self-contained validation modules. Developers must install a validator module
 * upon initialization (or any other mechanism to enable execution from the account):
 *
 * ```solidity
 * contract MyAccountERC7579 is AccountERC7579, Initializable {
 *     constructor() EIP712("MyAccountRSA", "1") {}
 *
 *   function initializeAccount(address validator, bytes calldata validatorData) public initializer {
 *     _installModule(MODULE_TYPE_VALIDATOR, validator, validatorData);
 *   }
 * }
 * ```
 *
 * NOTE: Hook support is not included. See {AccountERC7579Hooked} for a version that hooks to execution.
 */
abstract contract AccountERC7579 is
    AccountCore,
    ERC7739,
    IERC7579Execution,
    IERC7579AccountConfig,
    IERC7579ModuleConfig
{
    using Bytes for *;
    using ERC7579Utils for *;
    using EnumerableSet for *;
    using Packing for bytes32;

    EnumerableSet.AddressSet private _validators;
    EnumerableSet.AddressSet private _executors;
    mapping(bytes4 selector => address) private _fallbacks;

    /// @dev The account's {fallback} was called with a selector that doesn't have an installed handler.
    error ERC7579MissingFallbackHandler(bytes4 selector);

    /// @dev Modifier that checks if the caller is an installed module of the given type.
    modifier onlyModule(uint256 moduleTypeId) {
        _checkModule(moduleTypeId, msg.sender);
        _;
    }

    /// @inheritdoc IERC7579AccountConfig
    function accountId() public view virtual returns (string memory) {
        // vendorname.accountname.semver
        return "@openzeppelin/community-contracts.AccountERC7579.v0.0.0";
    }

    /**
     * @dev Returns whether the account supports the given execution mode.
     *
     * Supported call types:
     * * Single (`0x00`): A single transaction execution.
     * * Batch (`0x01`): A batch of transactions execution.
     * * Delegate (`0xff`): A delegate call execution.
     *
     * Supported exec types:
     * * Default (`0x00`): Default execution type (revert on failure).
     * * Try (`0x01`): Try execution type (emits ERC7579TryExecuteFail on failure).
     */
    function supportsExecutionMode(bytes32 encodedMode) public view virtual returns (bool) {
        (CallType callType, ExecType execType, , ) = Mode.wrap(encodedMode).decodeMode();
        return
            (callType == ERC7579Utils.CALLTYPE_SINGLE ||
                callType == ERC7579Utils.CALLTYPE_BATCH ||
                callType == ERC7579Utils.CALLTYPE_DELEGATECALL) &&
            (execType == ERC7579Utils.EXECTYPE_DEFAULT || execType == ERC7579Utils.EXECTYPE_TRY);
    }

    /**
     * @dev Returns whether the account supports the given module type.
     *
     * Supported module types:
     *
     * * Validator: A module used during the validation phase to determine if a transaction is valid and
     * should be executed on the account.
     * * Executor: A module that can execute transactions on behalf of the smart account via a callback.
     * * Fallback Handler: A module that can extend the fallback functionality of a smart account.
     */
    function supportsModule(uint256 moduleTypeId) public view virtual returns (bool) {
        return
            moduleTypeId == MODULE_TYPE_VALIDATOR ||
            moduleTypeId == MODULE_TYPE_EXECUTOR ||
            moduleTypeId == MODULE_TYPE_FALLBACK;
    }

    /// @inheritdoc IERC7579ModuleConfig
    function installModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata initData
    ) public virtual onlyEntryPointOrSelf {
        _installModule(moduleTypeId, module, initData);
    }

    /// @inheritdoc IERC7579ModuleConfig
    function uninstallModule(
        uint256 moduleTypeId,
        address module,
        bytes calldata deInitData
    ) public virtual onlyEntryPointOrSelf {
        _uninstallModule(moduleTypeId, module, deInitData);
    }

    /// @inheritdoc IERC7579ModuleConfig
    function isModuleInstalled(
        uint256 moduleTypeId,
        address module,
        bytes calldata additionalContext
    ) public view virtual returns (bool) {
        if (moduleTypeId == MODULE_TYPE_VALIDATOR) return _validators.contains(module);
        if (moduleTypeId == MODULE_TYPE_EXECUTOR) return _executors.contains(module);
        if (moduleTypeId == MODULE_TYPE_FALLBACK) return _fallbacks[bytes4(additionalContext[0:4])] == module;
        return false;
    }

    /// @dev Executes a transaction from the entry point or the account itself. See {_execute}.
    function execute(bytes32 mode, bytes calldata executionCalldata) public payable virtual onlyEntryPointOrSelf {
        _execute(Mode.wrap(mode), executionCalldata);
    }

    /// @dev Executes a transaction from the executor module. See {_execute}.
    function executeFromExecutor(
        bytes32 mode,
        bytes calldata executionCalldata
    ) public payable virtual onlyModule(MODULE_TYPE_EXECUTOR) returns (bytes[] memory returnData) {
        return _execute(Mode.wrap(mode), executionCalldata);
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
        address module = _extractUserOpValidator(userOp);
        return
            isModuleInstalled(MODULE_TYPE_VALIDATOR, module, Calldata.emptyBytes())
                ? IERC7579Validator(module).validateUserOp(userOp, _signableUserOpHash(userOp, userOpHash))
                : super._validateUserOp(userOp, userOpHash);
    }

    /**
     * @dev ERC-7579 execution logic. See {supportsExecutionMode} for supported modes.
     *
     * Reverts if the call type is not supported.
     */
    function _execute(
        Mode mode,
        bytes calldata executionCalldata
    ) internal virtual returns (bytes[] memory returnData) {
        (CallType callType, ExecType execType, , ) = mode.decodeMode();
        if (callType == ERC7579Utils.CALLTYPE_SINGLE) return executionCalldata.execSingle(execType);
        if (callType == ERC7579Utils.CALLTYPE_BATCH) return executionCalldata.execBatch(execType);
        if (callType == ERC7579Utils.CALLTYPE_DELEGATECALL) return executionCalldata.execDelegateCall(execType);
        revert ERC7579Utils.ERC7579UnsupportedCallType(callType);
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
        if (signature.length < 20) return false;
        address module = _extractSignatureValidator(signature);
        return
            isModuleInstalled(MODULE_TYPE_VALIDATOR, module, msg.data) &&
            IERC7579Validator(module).isValidSignatureWithSender(address(this), hash, signature[20:]) ==
            IERC1271.isValidSignature.selector;
    }

    /// @dev Checks if the module is installed. Reverts if the module is not installed.
    function _checkModule(uint256 moduleTypeId, address module) internal view virtual {
        require(
            isModuleInstalled(moduleTypeId, module, msg.data),
            ERC7579Utils.ERC7579UninstalledModule(moduleTypeId, module)
        );
    }

    /**
     * @dev Installs a module of the given type with the given initialization data.
     *
     * For the fallback module type, the `initData` is expected to be a tuple of a 4-byte selector and the
     * rest of the data to be sent to the handler when calling {IERC7579Module-onInstall}.
     *
     * Requirements:
     *
     * * Module type must be supported. See {supportsModule}. Reverts with {ERC7579UnsupportedModuleType}.
     * * Module must be of the given type. Reverts with {ERC7579MismatchedModuleTypeId}.
     * * Module must not be already installed. Reverts with {ERC7579AlreadyInstalledModule}.
     *
     * Emits a {ModuleInstalled} event.
     */
    function _installModule(uint256 moduleTypeId, address module, bytes memory initData) internal virtual {
        require(supportsModule(moduleTypeId), ERC7579Utils.ERC7579UnsupportedModuleType(moduleTypeId));
        require(
            IERC7579Module(module).isModuleType(moduleTypeId),
            ERC7579Utils.ERC7579MismatchedModuleTypeId(moduleTypeId, module)
        );

        if (moduleTypeId == MODULE_TYPE_VALIDATOR) {
            require(_validators.add(module), ERC7579Utils.ERC7579AlreadyInstalledModule(moduleTypeId, module));
        } else if (moduleTypeId == MODULE_TYPE_EXECUTOR) {
            require(_executors.add(module), ERC7579Utils.ERC7579AlreadyInstalledModule(moduleTypeId, module));
        } else if (moduleTypeId == MODULE_TYPE_FALLBACK) {
            bytes4 selector;
            (selector, initData) = _decodeFallbackData(initData);
            require(
                _fallbacks[selector] == address(0),
                ERC7579Utils.ERC7579AlreadyInstalledModule(moduleTypeId, module)
            );
            _fallbacks[selector] = module;
        }

        IERC7579Module(module).onInstall(initData);
        emit ModuleInstalled(moduleTypeId, module);
    }

    /**
     * @dev Uninstalls a module of the given type with the given de-initialization data.
     *
     * For the fallback module type, the `deInitData` is expected to be a tuple of a 4-byte selector and the
     * rest of the data to be sent to the handler when calling {IERC7579Module-onUninstall}.
     *
     * Requirements:
     *
     * * Module must be already installed. Reverts with {ERC7579UninstalledModule} otherwise.
     */
    function _uninstallModule(uint256 moduleTypeId, address module, bytes memory deInitData) internal virtual {
        if (moduleTypeId == MODULE_TYPE_VALIDATOR) {
            require(_validators.remove(module), ERC7579Utils.ERC7579UninstalledModule(moduleTypeId, module));
        } else if (moduleTypeId == MODULE_TYPE_EXECUTOR) {
            require(_executors.remove(module), ERC7579Utils.ERC7579UninstalledModule(moduleTypeId, module));
        } else if (moduleTypeId == MODULE_TYPE_FALLBACK) {
            bytes4 selector;
            (selector, deInitData) = _decodeFallbackData(deInitData);
            require(
                _fallbackHandler(selector) == module && module != address(0),
                ERC7579Utils.ERC7579UninstalledModule(moduleTypeId, module)
            );
            delete _fallbacks[selector];
        }

        IERC7579Module(module).onUninstall(deInitData);
        emit ModuleUninstalled(moduleTypeId, module);
    }

    /// @dev Returns the fallback handler for the given selector. Returns `address(0)` if not installed.
    function _fallbackHandler(bytes4 selector) internal view virtual returns (address) {
        return _fallbacks[selector];
    }

    /**
     * @dev Extracts the nonce validator from the user operation.
     *
     * To construct a nonce key, set nonce as follows:
     *
     * ```
     * <module address (20 bytes)> | <key (4 bytes)> | <nonce (8 bytes)>
     * ```
     */
    function _extractUserOpValidator(PackedUserOperation calldata userOp) internal pure virtual returns (address) {
        return address(bytes32(userOp.nonce).extract_32_20(0));
    }

    /**
     * @dev Extracts the signature validator from the signature.
     *
     * To construct a signature, set the first 20 bytes as the module address and the remaining bytes as the
     * signature data:
     *
     * ```
     * <module address (20 bytes)> | <signature data>
     * ```
     */
    function _extractSignatureValidator(bytes calldata signature) internal pure virtual returns (address) {
        return address(bytes20(signature[0:20]));
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

    /**
     * @dev Fallback function that delegates the call to the installed handler for the given selector.
     *
     * Reverts with {ERC7579MissingFallbackHandler} if the handler is not installed.
     *
     * Calls the handler with the original `msg.sender` appended at the end of the calldata following
     * the ERC-2771 format.
     */
    function _fallback() internal virtual returns (bytes memory) {
        address handler = _fallbackHandler(msg.sig);
        require(handler != address(0), ERC7579MissingFallbackHandler(msg.sig));

        // From https://eips.ethereum.org/EIPS/eip-7579#fallback[ERC-7579 specifications]:
        // - MUST utilize ERC-2771 to add the original msg.sender to the calldata sent to the fallback handler
        // - MUST use call to invoke the fallback handler
        (bool success, bytes memory returndata) = handler.call{value: msg.value}(
            abi.encodePacked(msg.data, msg.sender)
        );

        if (success) return returndata;

        assembly ("memory-safe") {
            revert(add(returndata, 0x20), mload(returndata))
        }
    }

    /// @dev See {_fallback}.
    fallback(bytes calldata) external payable virtual returns (bytes memory) {
        return _fallback();
    }
}
