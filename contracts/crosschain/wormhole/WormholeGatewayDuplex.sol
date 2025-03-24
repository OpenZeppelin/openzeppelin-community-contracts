// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {WormholeGatewayBase, IWormholeRelayer} from "./WormholeGatewayBase.sol";
import {WormholeGatewayDestination} from "./WormholeGatewayDestination.sol";
import {WormholeGatewaySource} from "./WormholeGatewaySource.sol";

/**
 * @dev A contract that combines the functionality of both the source and destination gateway
 * adapters for the Wormhole Network. Allowing to either send or receive messages across chains.
 */
// slither-disable-next-line locked-ether
contract WormholeGatewayDuplex is WormholeGatewaySource, WormholeGatewayDestination {
    /// @dev Initializes the contract with the Wormhole gateway and the initial owner.
    constructor(
        IWormholeRelayer gateway,
        uint16 wormholeChainId,
        address initialOwner
    ) Ownable(initialOwner) WormholeGatewayBase(gateway, wormholeChainId) {}
}
