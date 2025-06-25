// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IWormholeRelayer} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";

abstract contract WormholeGatewayBase is Ownable {
    using InteroperableAddress for bytes;

    IWormholeRelayer internal immutable _wormholeRelayer;
    uint16 internal immutable _wormholeChainId;

    // Remote gateway.
    // `addr` is the isolated address part of ERC-7930. Its not a full ERC-7930 interoperable address.
    mapping(bytes2 chainType => mapping(bytes chainReference => bytes32 addr)) private _remoteGateways;

    // chain equivalence ERC-7930 (no address) <> Wormhole
    mapping(bytes erc7930 => uint24 wormholeId) private _erc7930ToWormhole;
    mapping(uint16 wormholeId => bytes erc7930) private _wormholeToErc7930;

    /// @dev A remote gateway has been registered for a chain.
    event RegisteredRemoteGateway(bytes remote);

    /// @dev A chain equivalence has been registered.
    event RegisteredChainEquivalence(bytes erc7930binary, uint16 wormholeId);

    /// @dev Error emitted when an unsupported chain is queried.
    error UnsupportedERC7930Chain(bytes erc7930binary);
    error UnsupportedWormholeChain(uint16 wormholeId);
    error InvalidChainIdentifier(bytes erc7930binary);
    error ChainEquivalenceAlreadyRegistered(bytes erc7930binary, uint16 wormhole);
    error RemoteGatewayAlreadyRegistered(bytes2 chainType, bytes chainReference);
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
        (bytes2 chainType, bytes memory chainReference, ) = chain.parseV1();
        return _erc7930ToWormhole[InteroperableAddress.formatV1(chainType, chainReference, "")] & (1 << 16) != 0;
    }

    function getWormholeChain(bytes memory chain) public view virtual returns (uint16) {
        (bytes2 chainType, bytes memory chainReference, ) = chain.parseV1();
        uint24 wormholeId = _erc7930ToWormhole[InteroperableAddress.formatV1(chainType, chainReference, "")];
        require(wormholeId & (1 << 16) != 0, UnsupportedERC7930Chain(chain));
        return uint16(wormholeId);
    }

    function getErc7930Chain(uint16 wormholeId) public view virtual returns (bytes memory output) {
        output = _wormholeToErc7930[wormholeId];
        require(output.length > 0, UnsupportedWormholeChain(wormholeId));
    }

    /// @dev Returns the address of the remote gateway for a given chainType and chainReference.
    function getRemoteGateway(bytes memory chain) public view virtual returns (bytes32) {
        (bytes2 chainType, bytes memory chainReference, ) = chain.parseV1();
        return getRemoteGateway(chainType, chainReference);
    }

    function getRemoteGateway(bytes2 chainType, bytes memory chainReference) public view virtual returns (bytes32) {
        bytes32 addr = _remoteGateways[chainType][chainReference];
        if (addr == 0) revert UnsupportedERC7930Chain(InteroperableAddress.formatV1(chainType, chainReference, ""));
        return addr;
    }

    function registerChainEquivalence(bytes calldata chain, uint16 wormholeId) public virtual onlyOwner {
        (, , bytes calldata addr) = chain.parseV1Calldata();
        require(addr.length == 0, InvalidChainIdentifier(chain));
        require(
            _erc7930ToWormhole[chain] == 0 && _wormholeToErc7930[wormholeId].length == 0,
            ChainEquivalenceAlreadyRegistered(chain, wormholeId)
        );

        _erc7930ToWormhole[chain] = wormholeId | (1 << 16);
        _wormholeToErc7930[wormholeId] = chain;
        emit RegisteredChainEquivalence(chain, wormholeId);
    }

    function registerRemoteGateway(bytes calldata remote) public virtual onlyOwner {
        (bytes2 chainType, bytes calldata chainReference, bytes calldata addr) = remote.parseV1Calldata();
        require(
            _remoteGateways[chainType][chainReference] == 0,
            RemoteGatewayAlreadyRegistered(chainType, chainReference)
        );
        require(addr.length <= 32); // TODO: error if that is not an valid universal address
        _remoteGateways[chainType][chainReference] = bytes32(addr) >> (256 - 8 * addr.length); // align right
        emit RegisteredRemoteGateway(remote);
    }
}
