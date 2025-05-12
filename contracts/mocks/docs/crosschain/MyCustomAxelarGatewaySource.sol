// contracts/MyERC7786ReceiverContract.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AxelarGatewaySource} from "../../../crosschain/axelar/AxelarGatewaySource.sol";
import {AxelarGatewayBase} from "../../../crosschain/axelar/AxelarGatewayBase.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";

abstract contract MyCustomAxelarGatewaySource is AxelarGatewaySource {
    /// @dev Initializes the contract with the Axelar gateway and the initial owner.
    constructor(IAxelarGateway gateway, address initialOwner) Ownable(initialOwner) AxelarGatewayBase(gateway) {}
}
