// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7579Executor} from "../../../account/modules/ERC7579Executor.sol";
import {ERC7579Multisig} from "../../../account/modules/ERC7579Multisig.sol";
import {ERC7579MultisigWeighted} from "../../../account/modules/ERC7579MultisigWeighted.sol";
import {MODULE_TYPE_EXECUTOR, IERC7579Hook} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

abstract contract ERC7579MultisigExecutorMock is ERC7579Executor, ERC7579Multisig {}
abstract contract ERC7579MultisigWeightedExecutorMock is ERC7579Executor, ERC7579MultisigWeighted {}
