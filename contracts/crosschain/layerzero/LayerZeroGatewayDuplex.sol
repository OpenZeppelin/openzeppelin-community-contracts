// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {LayerZeroGatewayBase} from "./LayerZeroGatewayBase.sol";
import {LayerZeroGatewayDestination} from "./LayerZeroGatewayDestination.sol";
import {LayerZeroGatewaySource} from "./LayerZeroGatewaySource.sol";

/**
 * @dev A contract that combines the functionality of both the source and destination gateway
 * adapters for the LayerZero Network. Allowing to either send or receive messages across chains.
 */
// slither-disable-next-line locked-ether
contract LayerZeroGatewayDuplex is LayerZeroGatewaySource, LayerZeroGatewayDestination {
    /// @dev Initializes the contract with the LayerZero endpoint and the initial owner.
    constructor(
        ILayerZeroEndpointV2 layerZeroEndpoint,
        address initialOwner
    ) Ownable(initialOwner) LayerZeroGatewayBase(layerZeroEndpoint) {}
}
