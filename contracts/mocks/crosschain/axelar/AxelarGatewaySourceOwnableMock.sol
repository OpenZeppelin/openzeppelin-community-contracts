// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AxelarGatewaySource} from "../../../crosschain/axelar/AxelarGatewaySource.sol";

abstract contract AxelarGatewaySourceOwnableMock is AxelarGatewaySource, Ownable {
    function _authorizeRegistrant() internal override onlyOwner {}
}
