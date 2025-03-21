// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IWormholeRelayer} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol"; // VaaKey

abstract contract WormholeGatewayBase is Ownable {
    IWormholeRelayer internal immutable _wormholeRelayer;
    uint16 internal immutable _currentChain;

    mapping(string caip2 => bytes32 remoteGateway) private _remoteGateways;
    mapping(string caip2 => uint24 wormholeId) private _caipToWormholeEquivalence;
    mapping(uint16 wormholeId => string caip2) private _wormholeToCaipEquivalence;

    /// @dev A remote gateway has been registered for a chain.
    event RegisteredRemoteGateway(string caip2, bytes32 gatewayAddress);

    /// @dev A chain equivalence has been registered.
    event RegisteredChainEquivalence(string caip2, uint16 wormholeId);

    /// @dev Error emitted when an unsupported chain is queried.
    error UnsupportedChain(string caip2);
    error UnsupportedChain2(uint16 wormholeId);

    error ChainEquivalenceAlreadyRegistered(string caip2);
    error RemoteGatewayAlreadyRegistered(string caip2);
    error UnauthorizedCaller(address);

    modifier onlyWormholeRelayer() {
        require(msg.sender == address(_wormholeRelayer), UnauthorizedCaller(msg.sender));
        _;
    }

    constructor(IWormholeRelayer wormholeRelayer, uint16 currentChain) {
        _wormholeRelayer = wormholeRelayer;
        _currentChain = currentChain;
    }

    function gateway() public view virtual returns (address) {
        return address(_wormholeRelayer);
    }

    function supportedChain(string memory caip2) public view virtual returns (bool) {
        return _caipToWormholeEquivalence[caip2] & (1 << 16) != 0;
    }

    function fromCAIP2(string memory caip2) public view virtual returns (uint16) {
        uint24 wormholeId = _caipToWormholeEquivalence[caip2];
        require(wormholeId & (1 << 16) != 0, UnsupportedChain(caip2));
        return uint16(wormholeId);
    }

    function toCAIP2(uint16 wormholeId) public view virtual returns (string memory caip2) {
        caip2 = _wormholeToCaipEquivalence[wormholeId];
        require(bytes(caip2).length > 0, UnsupportedChain2(wormholeId));
    }

    function getRemoteGateway(string memory caip2) public view virtual returns (bytes32 remoteGateway) {
        remoteGateway = _remoteGateways[caip2];
        require(remoteGateway != bytes32(0), UnsupportedChain(caip2));
    }

    function registerChainEquivalence(string calldata caip2, uint16 wormholeId) public virtual onlyOwner {
        require(_caipToWormholeEquivalence[caip2] == 0, ChainEquivalenceAlreadyRegistered(caip2));
        _caipToWormholeEquivalence[caip2] = wormholeId | (1 << 16);
        _wormholeToCaipEquivalence[wormholeId] = caip2;
        emit RegisteredChainEquivalence(caip2, wormholeId);
    }

    function registerRemoteGateway(string calldata caip2, bytes32 remoteGateway) public virtual onlyOwner {
        require(_remoteGateways[caip2] == bytes32(0), RemoteGatewayAlreadyRegistered(caip2));
        _remoteGateways[caip2] = remoteGateway;
        emit RegisteredRemoteGateway(caip2, remoteGateway);
    }
}
