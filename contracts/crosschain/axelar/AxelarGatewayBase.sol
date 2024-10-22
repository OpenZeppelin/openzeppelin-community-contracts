// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";

abstract contract AxelarGatewayBase is Ownable {
    event RegisteredRemoteGateway(string caip2, string gatewayAddress);
    event RegisteredChainEquivalence(string caip2, string destinationChain);

    error UnsupportedChain(string caip2);

    IAxelarGateway public immutable localGateway;

    mapping(string caip2 => string remoteGateway) private _remoteGateways;
    mapping(string caip2OrAxelar => string axelarOfCaip2) private _chainEquivalence;

    constructor(IAxelarGateway _gateway) {
        localGateway = _gateway;
    }

    function getEquivalentChain(string memory input) public view virtual returns (string memory output) {
        output = _chainEquivalence[input];
        require(bytes(output).length > 0, UnsupportedChain(input));
    }

    function getRemoteGateway(string memory caip2) public view virtual returns (string memory remoteGateway) {
        remoteGateway = _remoteGateways[caip2];
        require(bytes(remoteGateway).length > 0, UnsupportedChain(caip2));
    }

    function registerChainEquivalence(string calldata caip2, string calldata axelarSupported) public virtual onlyOwner {
        require(bytes(_chainEquivalence[caip2]).length == 0);
        _chainEquivalence[caip2] = axelarSupported;
        _chainEquivalence[axelarSupported] = caip2;
        emit RegisteredChainEquivalence(caip2, axelarSupported);
    }

    function registerRemoteGateway(string calldata caip2, string calldata remoteGateway) public virtual onlyOwner {
        require(bytes(_remoteGateways[caip2]).length == 0);
        _remoteGateways[caip2] = remoteGateway;
        emit RegisteredRemoteGateway(caip2, remoteGateway);
    }
}
