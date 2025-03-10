// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AxelarGatewayBase, IAxelarGateway} from "./AxelarGatewayBase.sol";
import {AxelarGatewayDestination, AxelarExecutable} from "./AxelarGatewayDestination.sol";
import {AxelarGatewaySource} from "./AxelarGatewaySource.sol";

/**
 * @dev A contract that combines the functionality of both the source and destination gateway
 * adapters for the Axelar Network. Allowing to either send or receive messages across chains.
 */
// slither-disable-next-line locked-ether
contract AxelarGatewayDuplex is AxelarGatewaySource, AxelarGatewayDestination {
    /// @dev Initializes the contract with the Axelar gateway and the initial owner.
    constructor(
        IAxelarGateway gateway,
        address initialOwner
    ) Ownable(initialOwner) AxelarGatewayBase(gateway) AxelarExecutable(address(gateway)) {}
}
