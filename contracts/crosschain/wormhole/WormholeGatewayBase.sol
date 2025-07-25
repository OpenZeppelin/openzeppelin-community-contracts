// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IWormholeRelayer} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";

/// Note: only EVM chains are currently supported
abstract contract WormholeGatewayBase is Ownable {
    using InteroperableAddress for bytes;

    IWormholeRelayer internal immutable _wormholeRelayer;
    uint16 internal immutable _wormholeChainId;
    uint24 private constant MASK = 1 << 16;

    // Remote gateway.
    mapping(uint256 chainId => address) private _remoteGateways;

    // chain equivalence ChainId <> Wormhole
    mapping(uint256 chainId => uint24 wormholeId) private _chainIdToWormhole;
    mapping(uint16 wormholeId => uint256 chainId) private _wormholeToChainId;

    /// @dev A remote gateway has been registered for a chain.
    event RegisteredRemoteGateway(uint256 chainId, address remote);

    /// @dev A chain equivalence has been registered.
    event RegisteredChainEquivalence(uint256 chainId, uint16 wormholeId);

    error UnsupportedChainId(uint256 chainId);
    error UnsupportedWormholeChain(uint16 wormholeId);
    error ChainEquivalenceAlreadyRegistered(uint256 chainId, uint16 wormhole);
    error RemoteGatewayAlreadyRegistered(uint256 chainId);
    error UnauthorizedCaller(address);

    modifier onlyWormholeRelayer() {
        require(msg.sender == address(_wormholeRelayer), UnauthorizedCaller(msg.sender));
        _;
    }

    constructor(IWormholeRelayer wormholeRelayer, uint16 wormholeChainId) {
        _wormholeRelayer = wormholeRelayer;
        _wormholeChainId = wormholeChainId;
    }

    function relayer() public view virtual returns (address) {
        return address(_wormholeRelayer);
    }

    function supportedChain(bytes memory chain) public view virtual returns (bool) {
        (bool success, uint256 chainId, ) = chain.tryParseEvmV1();
        return success && supportedChain(chainId);
    }

    function supportedChain(uint256 chainId) public view virtual returns (bool) {
        return _chainIdToWormhole[chainId] & MASK == MASK;
    }

    function getWormholeChain(bytes memory chain) public view virtual returns (uint16) {
        (uint256 chainId, ) = chain.parseEvmV1();
        return getWormholeChain(chainId);
    }

    function getWormholeChain(uint256 chainId) public view virtual returns (uint16) {
        uint24 wormholeId = _chainIdToWormhole[chainId];
        require(wormholeId & MASK == MASK, UnsupportedChainId(chainId));
        return uint16(wormholeId);
    }

    function getChainId(uint16 wormholeId) public view virtual returns (uint256) {
        uint256 chainId = _wormholeToChainId[wormholeId];
        require(chainId != 0, UnsupportedWormholeChain(wormholeId));
        return chainId;
    }

    /// @dev Returns the address of the remote gateway for a given chainType and chainReference.
    function getRemoteGateway(bytes memory chain) public view virtual returns (address) {
        (uint256 chainId, ) = chain.parseEvmV1();
        return getRemoteGateway(chainId);
    }

    function getRemoteGateway(uint256 chainId) public view virtual returns (address) {
        address addr = _remoteGateways[chainId];
        require(addr != address(0), UnsupportedChainId(chainId));
        return addr;
    }

    function registerChainEquivalence(
        bytes calldata chain,
        uint16 wormholeId
    ) public virtual /*onlyOwner in registerChainEquivalence*/ {
        (uint256 chainId, ) = chain.parseEvmV1Calldata();
        registerChainEquivalence(chainId, wormholeId);
    }

    function registerChainEquivalence(uint256 chainId, uint16 wormholeId) public virtual onlyOwner {
        require(
            _chainIdToWormhole[chainId] == 0 && _wormholeToChainId[wormholeId] == 0,
            ChainEquivalenceAlreadyRegistered(chainId, wormholeId)
        );

        _chainIdToWormhole[chainId] = wormholeId | MASK;
        _wormholeToChainId[wormholeId] = chainId;
        emit RegisteredChainEquivalence(chainId, wormholeId);
    }

    function registerRemoteGateway(bytes calldata remote) public virtual /*onlyOwner in registerRemoteGateway*/ {
        (uint256 chainId, address addr) = remote.parseEvmV1Calldata();
        registerRemoteGateway(chainId, addr);
    }

    function registerRemoteGateway(uint256 chainId, address addr) public virtual onlyOwner {
        require(supportedChain(chainId), UnsupportedChainId(chainId));
        require(_remoteGateways[chainId] == address(0), RemoteGatewayAlreadyRegistered(chainId));
        _remoteGateways[chainId] = addr;
        emit RegisteredRemoteGateway(chainId, addr);
    }
}
