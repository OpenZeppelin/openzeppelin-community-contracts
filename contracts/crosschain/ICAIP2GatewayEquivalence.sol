// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IAxelarGateway} from "./vendor/axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "./vendor/axelar/interfaces/IAxelarGasService.sol";
import {CAIP2} from "../utils/CAIP-2.sol";

interface IGatewayCAIP2Equivalence {
    function registerCAIP2Equivalence(CAIP2.ChainId memory chain, bytes memory custom) public;
    function isRegisteredCAIP2(CAIP2.ChainId memory chain) public view returns (bool);
    function fromCAIP2(CAIP2.ChainId memory chain) public pure returns (bytes memory);
}
