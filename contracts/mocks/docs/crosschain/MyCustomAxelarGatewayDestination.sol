// contracts/MyCustomAxelarGatewayDestination.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AxelarGatewayDestination, AxelarExecutable} from "../../../crosschain/axelar/AxelarGatewayDestination.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";

abstract contract MyCustomAxelarGatewayDestination is AxelarGatewayDestination {
    /// @dev Initializes the contract with the Axelar gateway and the initial owner.
    constructor(IAxelarGateway gateway, address initialOwner) AxelarExecutable(address(gateway)) {}
}
