// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract GatewayAdapterBase is Ownable {
    event RegisteredRemoteGateway(string caip2, string gatewayAddress);

    mapping(string caip2 => string remoteGateway) private _remoteGateways;

    function getRemoteGateway(string memory caip2) public view returns (string memory remoteGateway) {
        return _remoteGateways[caip2];
    }

    function registerRemoteGateway(string calldata caip2, string calldata remoteGateway) public onlyOwner {
        require(bytes(_remoteGateways[caip2]).length == 0);
        _remoteGateways[caip2] = remoteGateway;
        emit RegisteredRemoteGateway(caip2, remoteGateway);
    }
}
