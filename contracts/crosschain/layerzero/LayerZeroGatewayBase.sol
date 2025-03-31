// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

abstract contract LayerZeroGatewayBase is Ownable {
    ILayerZeroEndpointV2 internal immutable _layerZeroEndpoint;

    mapping(string caip2 => bytes32 remoteGateway) private _remoteGateways;
    mapping(string caip2 => uint40 layerZeroId) private _caipToLayerZeroEquivalence;
    mapping(uint32 layerZeroId => string caip2) private _layerZeroToCaipEquivalence;

    /// @dev A remote gateway has been registered for a chain.
    event RegisteredRemoteGateway(string caip2, bytes32 gatewayAddress);

    /// @dev A chain equivalence has been registered.
    event RegisteredChainEquivalence(string caip2, uint32 layerZeroId);

    // /// @dev Error emitted when an unsupported chain is queried.
    error UnsupportedChain(string caip2);
    error UnsupportedChain2(uint32 layerZeroId);
    error ChainEquivalenceAlreadyRegistered(string caip2);
    error RemoteGatewayAlreadyRegistered(string caip2);
    error UnauthorizedCaller(address);

    modifier onlyLayerZeroEndpoint() {
        require(msg.sender == address(_layerZeroEndpoint), UnauthorizedCaller(msg.sender));
        _;
    }

    constructor(ILayerZeroEndpointV2 layerZeroEndpoint) {
        _layerZeroEndpoint = layerZeroEndpoint;
    }

    function endpoint() public view virtual returns (address) {
        return address(_layerZeroEndpoint);
    }

    function supportedChain(string memory caip2) public view virtual returns (bool) {
        return _caipToLayerZeroEquivalence[caip2] & (1 << 32) != 0;
    }

    function fromCAIP2(string memory caip2) public view virtual returns (uint32) {
        uint40 layerZeroId = _caipToLayerZeroEquivalence[caip2];
        require(layerZeroId & (1 << 32) != 0, UnsupportedChain(caip2));
        return uint32(layerZeroId);
    }

    function toCAIP2(uint32 layerZeroId) public view virtual returns (string memory caip2) {
        caip2 = _layerZeroToCaipEquivalence[layerZeroId];
        require(bytes(caip2).length > 0, UnsupportedChain2(layerZeroId));
    }

    function getRemoteGateway(string memory caip2) public view virtual returns (bytes32 remoteGateway) {
        remoteGateway = _remoteGateways[caip2];
        require(remoteGateway != bytes32(0), UnsupportedChain(caip2));
    }

    function registerChainEquivalence(string calldata caip2, uint32 layerZeroId) public virtual onlyOwner {
        require(_caipToLayerZeroEquivalence[caip2] == 0, ChainEquivalenceAlreadyRegistered(caip2));
        _caipToLayerZeroEquivalence[caip2] = layerZeroId | (1 << 32);
        _layerZeroToCaipEquivalence[layerZeroId] = caip2;
        emit RegisteredChainEquivalence(caip2, layerZeroId);
    }

    function registerRemoteGateway(string calldata caip2, bytes32 remoteGateway) public virtual onlyOwner {
        require(_remoteGateways[caip2] == bytes32(0), RemoteGatewayAlreadyRegistered(caip2));
        _remoteGateways[caip2] = remoteGateway;
        emit RegisteredRemoteGateway(caip2, remoteGateway);
    }
}
