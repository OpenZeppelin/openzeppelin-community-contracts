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

    error UnsupportedExecutionMode();

    /// @inheritdoc IERC7821
    function execute(bytes32 mode, bytes calldata executionData) public payable virtual onlyEntryPointOrSelf {
        if (!supportsExecutionMode(mode)) revert UnsupportedExecutionMode();
        executionData.execBatch(ERC7579Utils.EXECTYPE_DEFAULT);
    }

    /// @inheritdoc IERC7821
    function supportsExecutionMode(bytes32 mode) public view virtual returns (bool result) {
        (CallType callType, ExecType execType, ModeSelector modeSelector, ) = Mode.wrap(mode).decodeMode();
        return
            callType == ERC7579Utils.CALLTYPE_BATCH &&
            execType == ERC7579Utils.EXECTYPE_DEFAULT &&
            modeSelector == ModeSelector.wrap(0x00000000);
    }
}
