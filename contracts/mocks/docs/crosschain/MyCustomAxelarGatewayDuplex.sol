// contracts/MyCustomAxelarGatewayDuplex.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AxelarGatewayDuplex, AxelarExecutable} from "../../../crosschain/axelar/AxelarGatewayDuplex.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";

abstract contract MyCustomAxelarGatewayDuplex is AxelarGatewayDuplex {
    /// @dev Initializes the contract with the Axelar gateway and the initial owner.
    constructor(IAxelarGateway gateway, address initialOwner) AxelarGatewayDuplex(gateway, initialOwner) {}
}
