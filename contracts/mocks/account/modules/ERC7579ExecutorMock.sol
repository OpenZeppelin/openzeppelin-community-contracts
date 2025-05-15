// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Mode} from "@openzeppelin/contracts/account/utils/draft-ERC7579Utils.sol";
import {ERC7579Executor} from "../../../account/modules/ERC7579Executor.sol";

contract ERC7579ExecutorMock is ERC7579Executor {
    function onInstall(bytes calldata) public virtual {}

    function onUninstall(bytes calldata) public virtual {}

    function _validateExecution(
        address account,
        Mode /* mode */,
        bytes calldata /* executionCalldata */,
        bytes32 /* salt */
    ) internal view override {
        if (account != msg.sender) revert ERC7579UnauthorizedExecution();
    }
}
