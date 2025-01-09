// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AxelarGatewayDestination} from "../../../crosschain/axelar/AxelarGatewayDestination.sol";

abstract contract AxelarGatewayDestinationOwnableMock is AxelarGatewayDestination, Ownable {
    function _checkRegistrant() internal override onlyOwner {}
}
