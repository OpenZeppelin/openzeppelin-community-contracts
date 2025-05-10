// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7579Executor} from "../../../account/modules/ERC7579Executor.sol";
import {MODULE_TYPE_EXECUTOR, IERC7579Hook} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

abstract contract ERC7579ExecutorMock is ERC7579Executor {
    function onInstall(bytes calldata data) public view {}

    function onUninstall(bytes calldata data) public view {}
}
