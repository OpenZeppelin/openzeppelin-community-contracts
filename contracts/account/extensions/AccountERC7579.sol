// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {PackedUserOperation} from "@openzeppelin/contracts/interfaces/draft-IERC4337.sol";
import {IERC7579Module, IERC7579Validator, IERC7579Execution, IERC7579AccountConfig, IERC7579ModuleConfig, MODULE_TYPE_VALIDATOR, MODULE_TYPE_EXECUTOR, MODULE_TYPE_FALLBACK} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";
import {ERC7579Utils, Mode, CallType, ExecType} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC4337Utils} from "@openzeppelin/contracts/account/utils/draft-ERC4337Utils.sol";
import {ERC7739Signer} from "../../utils/cryptography/ERC7739Signer.sol";
import {AccountCore} from "../AccountCore.sol";

abstract contract AccountERC7579 is
    AccountCore,
    ERC7739Signer,
    IERC7579Execution,
    IERC7579AccountConfig,
    IERC7579ModuleConfig
{
    using ERC7579Utils for *;
    using EnumerableSet for *;

    EnumerableSet.AddressSet private _validators;
    EnumerableSet.AddressSet private _executors;
    mapping(bytes4 selector => address) private _fallbacks;

    error ERC7579MissingFallbackHandler(bytes4 selector);

    modifier onlyModule(uint256 moduleTypeId) {
        _checkModule(moduleTypeId, msg.sender);
        _;
    }

    /// @inheritdoc IERC7579AccountConfig
    function accountId() public view virtual returns (string memory) {
        //vendorname.accountname.semver
        return "@openzeppelin/contracts.erc7579account.v0-beta";
    }

    /// @inheritdoc IERC7579AccountConfig
    function supportsExecutionMode(bytes32 encodedMode) public view virtual returns (bool) {
        (CallType callType, , , ) = Mode.wrap(encodedMode).decodeMode();
        return
            callType == ERC7579Utils.CALLTYPE_SINGLE ||
            callType == ERC7579Utils.CALLTYPE_BATCH ||
            callType == ERC7579Utils.CALLTYPE_DELEGATECALL;
    }

    /// @inheritdoc IERC7579AccountConfig
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
        if (moduleTypeId == MODULE_TYPE_FALLBACK) return _fallbacks[bytes4(additionalContext[0:4])] != module;
        return false;
    }

    /// @inheritdoc IERC7579Execution
    function execute(bytes32 mode, bytes calldata executionCalldata) public virtual onlyEntryPointOrSelf {
        _execute(Mode.wrap(mode), executionCalldata);
    }

    /// @inheritdoc IERC7579Execution
    function executeFromExecutor(
        bytes32 mode,
        bytes calldata executionCalldata
    ) public virtual onlyModule(MODULE_TYPE_EXECUTOR) returns (bytes[] memory returnData) {
        return _execute(Mode.wrap(mode), executionCalldata);
    }

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

    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        if (signature.length < 20) return false;
        address module = address(bytes20(signature[0:20]));
        if (!isModuleInstalled(MODULE_TYPE_VALIDATOR, module, msg.data)) return false;
        return
            IERC7579Validator(module).isValidSignatureWithSender(msg.sender, hash, signature) ==
            IERC1271.isValidSignature.selector;
    }

    function _checkModule(uint256 moduleTypeId, address module) internal view virtual {
        require(
            isModuleInstalled(moduleTypeId, module, msg.data),
            ERC7579Utils.ERC7579UninstalledModule(moduleTypeId, module)
        );
    }

    function _installModule(uint256 moduleTypeId, address module, bytes memory initData) internal virtual {
        require(supportsModule(moduleTypeId), ERC7579Utils.ERC7579UnsupportedModuleType(moduleTypeId));
        require(
            IERC7579Module(module).isModuleType(moduleTypeId),
            ERC7579Utils.ERC7579MismatchedModuleTypeId(moduleTypeId, module)
        );

        require(
            (moduleTypeId != MODULE_TYPE_VALIDATOR || _validators.add(module)) ||
                (moduleTypeId != MODULE_TYPE_EXECUTOR || _executors.add(module)),
            ERC7579Utils.ERC7579AlreadyInstalledModule(moduleTypeId, module)
        );
        if (moduleTypeId == MODULE_TYPE_FALLBACK) {
            bytes4 selector;
            (selector, initData) = abi.decode(initData, (bytes4, bytes));
            require(
                _installFallback(module, selector),
                ERC7579Utils.ERC7579AlreadyInstalledModule(moduleTypeId, module)
            );
        }

        IERC7579Module(module).onInstall(initData);
        emit ModuleInstalled(moduleTypeId, module);
    }

    function _uninstallModule(uint256 moduleTypeId, address module, bytes memory deInitData) internal virtual {
        require(
            (moduleTypeId != MODULE_TYPE_VALIDATOR || _validators.remove(module)) ||
                (moduleTypeId != MODULE_TYPE_EXECUTOR || _executors.remove(module)),
            ERC7579Utils.ERC7579UninstalledModule(moduleTypeId, module)
        );

        if (moduleTypeId == MODULE_TYPE_FALLBACK) {
            bytes4 selector;
            (selector, deInitData) = abi.decode(deInitData, (bytes4, bytes));
            require(_uninstallFallback(module, selector), ERC7579Utils.ERC7579UninstalledModule(moduleTypeId, module));
        }

        IERC7579Module(module).onUninstall(deInitData);
        emit ModuleUninstalled(moduleTypeId, module);
    }

    function _installFallback(address module, bytes4 selector) internal virtual returns (bool) {
        if (_fallbacks[selector] != address(0)) return false;
        _fallbacks[selector] = module;
        return true;
    }

    function _uninstallFallback(address module, bytes4 selector) internal virtual returns (bool) {
        address handler = _fallbackHandler(selector);
        if (handler == address(0) || handler != module) return false;
        delete _fallbacks[selector];
        return true;
    }

    function _fallbackHandler(bytes4 selector) internal view virtual returns (address) {
        return _fallbacks[selector];
    }

    function _fallback() internal virtual {
        address handler = _fallbackHandler(msg.sig);
        if (handler == address(0)) revert ERC7579MissingFallbackHandler(msg.sig);

        // From https://eips.ethereum.org/EIPS/eip-7579#fallback[ERC-7579 specifications]:
        // - MUST utilize ERC-2771 to add the original msg.sender to the calldata sent to the fallback handler
        // - MUST use call to invoke the fallback handler
        (bool success, bytes memory returndata) = handler.call{value: msg.value}(
            abi.encodePacked(msg.data, msg.sender)
        );

        assembly ("memory-safe") {
            switch success
            case 0 {
                revert(add(returndata, 0x20), mload(returndata))
            }
            default {
                return(add(returndata, 0x20), mload(returndata))
            }
        }
    }

    // slither-disable-next-line write-after-write
    function _emptyCalldataBytes() private pure returns (bytes calldata result) {
        assembly ("memory-safe") {
            result.offset := 0
            result.length := 0
        }
    }

    fallback() external payable virtual {
        _fallback();
    }
}
