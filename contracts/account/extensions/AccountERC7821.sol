// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC7579Utils, Mode, CallType, ExecType, ModeSelector} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {IERC7821} from "../../interfaces/IERC7821.sol";
import {AccountCore} from "../AccountCore.sol";

/**
 * @dev Minimal batch executor following ERC7821. Only supports basic mode (no optional "opData").
 */
abstract contract AccountERC7821 is AccountCore, IERC7821 {
    using ERC7579Utils for *;

    ModeSelector private constant SIMPLE_MODE_SELECTOR = ModeSelector.wrap(0x00000000);
    ModeSelector private constant OPTIONAL_OPDATA_MODE_SELECTOR = ModeSelector.wrap(0x78210001);

    error UnsupportedExecutionMode();

    /// @inheritdoc IERC7821
    function execute(bytes32 mode, bytes calldata executionData) public payable virtual onlyEntryPointOrSelf {
        (ModeSelector modeSelector, bool supported) = _supportsExecutionMode(mode);
        require(supported, UnsupportedExecutionMode());
        if (modeSelector == SIMPLE_MODE_SELECTOR) executionData.execBatch(ERC7579Utils.EXECTYPE_DEFAULT);
        else {
            bytes calldata opData;
            (executionData, opData) = _decodeExecutionOpData(executionData);
            _verifyOpData(executionData, opData);
            executionData.execBatch(ERC7579Utils.EXECTYPE_DEFAULT);
        }
    }

    function _verifyOpData(bytes calldata executionData, bytes calldata opData) internal view virtual {
        // NO-OP by default
    }

    /// @inheritdoc IERC7821
    function supportsExecutionMode(bytes32 mode) public view virtual returns (bool) {
        (, bool result) = _supportsExecutionMode(mode);
        return result;
    }

    function _supportsExecutionMode(bytes32 mode) internal pure returns (ModeSelector modeSelector, bool supported) {
        (CallType callType, ExecType execType, ModeSelector selector, ) = Mode.wrap(mode).decodeMode();
        bool isSupportedSelector = selector == SIMPLE_MODE_SELECTOR || selector == OPTIONAL_OPDATA_MODE_SELECTOR;
        return (
            selector,
            (isSupportedSelector &&
                callType == ERC7579Utils.CALLTYPE_BATCH &&
                execType == ERC7579Utils.EXECTYPE_DEFAULT)
        );
    }

    function _decodeExecutionOpData(
        bytes calldata executionData
    ) internal pure returns (bytes calldata calls, bytes calldata opData) {
        // There should be at least 2 elements in the executionData (i.e. a tuple of 2 pointers)
        if (executionData.length < 64) return (executionData, _emptyCalldataBytes());

        assembly ("memory-safe") {
            let callsPtr := add(executionData.offset, calldataload(executionData.offset))
            calls.offset := add(callsPtr, 32)
            calls.length := calldataload(callsPtr)

            let opDataPtr := add(executionData.offset, calldataload(add(executionData.offset, 32)))
            opData.offset := add(opDataPtr, 32)
            opData.length := calldataload(opDataPtr)
        }
    }

    // slither-disable-next-line write-after-write
    function _emptyCalldataBytes() private pure returns (bytes calldata result) {
        assembly ("memory-safe") {
            result.offset := 0
            result.length := 0
        }
    }
}
