// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AxelarGatewayBase, IAxelarGateway} from "./AxelarGatewayBase.sol";
import {AxelarGatewayDestination, AxelarExecutable} from "./AxelarGatewayDestination.sol";
import {AxelarGatewaySource} from "./AxelarGatewaySource.sol";

contract AxelarGatewayDuplex is AxelarGatewaySource, AxelarGatewayDestination {
    constructor(
        IAxelarGateway gateway,
        address initialOwner
    ) Ownable(initialOwner) AxelarGatewayBase(gateway) AxelarExecutable(address(gateway)) {}
}
