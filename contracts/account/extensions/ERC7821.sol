// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC7579Utils, Mode, CallType, ExecType, ModeSelector} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {IERC7821} from "../../interfaces/IERC7821.sol";
import {AccountCore} from "../AccountCore.sol";

/**
 * @dev Minimal batch executor following ERC-7821. Only supports basic mode (no optional "opData").
 */
abstract contract ERC7821 is IERC7821 {
    using ERC7579Utils for *;

    error UnsupportedExecutionMode();

    /**
     * @dev Executes the calls in `executionData` with no optional `opData` support.
     *
     * NOTE: Access to this function is controlled by {_erc7821AuthorizedExecutor}. Changing access permissions, for
     * example to approve calls by the ERC-4337 entrypoint, should be implement by overriding it.
     *
     * Reverts and bubbles up error if any call fails.
     */
    function execute(bytes32 mode, bytes calldata executionData) public payable virtual {
        if (!_erc7821AuthorizedExecutor(mode, executionData)) revert AccountCore.AccountUnauthorized(msg.sender);
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

    /**
     * @dev Access control mechanism for the {execute} function.
     */
    function _erc7821AuthorizedExecutor(
        bytes32 /* mode */,
        bytes calldata /* executionData */
    ) internal view virtual returns (bool) {
        return msg.sender == address(this);
    }

    // slither-disable-next-line write-after-write
    function _emptyCalldataBytes() private pure returns (bytes calldata result) {
        assembly ("memory-safe") {
            result.offset := 0
            result.length := 0
        }
    }
}
