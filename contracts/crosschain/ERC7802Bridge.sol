// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC7786GatewaySource, IERC7786Receiver} from "../interfaces/IERC7786.sol";
import {IERC7802} from "../interfaces/IERC7802.sol";
import {ERC7930} from "../utils/ERC7930.sol";

abstract contract ERC7802Bridge is IERC7786Receiver, Ownable, Pausable {
    using BitMaps for BitMaps.BitMap;
    using ERC7930 for bytes;

    event Sent(address token, address from, bytes to, uint256 amount);
    event Received(address token, bytes from, address to, uint256 amount);

    event GatewayRegistered(address indexed gateway, bytes chain);
    event RemoteBridgeRegistered(address indexed token, bytes chain);

    error ERC7802BridgeMissingGateway(bytes chain);
    error ERC7802BridgeMissingRemote(address token, bytes chain);
    error ERC7802BridgeImproperChainIdentifier(bytes chain);
    error ERC7802BridgeDuplicate();
    error ERC7802BridgeInvalidGateway();
    error ERC7802BridgeInvalidSender();

    mapping(address token => mapping(bytes chain => bytes bridge)) private _remoteBridges;
    mapping(address token => mapping(bytes chain => bytes remote)) private _remoteTokens;
    mapping(bytes chain => address gateway) private _gateways;
    BitMaps.BitMap private _processed;

    function getGateway(bytes memory chain) public virtual returns (address gateway) {
        gateway = _gateways[chain];
        require(gateway != address(0), ERC7802BridgeMissingGateway(chain));
    }

    // TODO: check that gateway is not address(0) ? prevent  override ?
    function registerGateway(address gateway, bytes memory chain) public virtual onlyOwner {
        (, , bytes memory addr) = chain.parseV1();
        require(addr.length == 0, ERC7802BridgeImproperChainIdentifier(chain));

        _gateways[chain] = gateway;

        emit GatewayRegistered(gateway, chain);
    }

    function getRemoteBridge(address token, bytes memory chain) public virtual returns (bytes memory bridge) {
        bridge = _remoteBridges[token][chain];
        require(bridge.length > 0, ERC7802BridgeMissingRemote(token, chain));
    }

    function getRemoteToken(address token, bytes memory chain) public virtual returns (bytes memory remote) {
        remote = _remoteTokens[token][chain];
        require(remote.length > 0, ERC7802BridgeMissingRemote(token, chain));
    }

    // TODO: check that bridge includes an address ? prevent override ?
    function registerRemote(address token, bytes memory bridge, bytes memory remote) public virtual onlyOwner {
        (bytes2 chainType, bytes memory chainReference, ) = bridge.parseV1();
        bytes memory chain = ERC7930.formatV1(chainType, chainReference, "");

        _remoteBridges[token][chain] = bridge;
        _remoteTokens[token][chain] = remote;

        emit RemoteBridgeRegistered(token, chain);
    }

    function send(
        address token,
        bytes memory to,
        uint256 amount,
        bytes[] memory attributes
    ) public payable virtual returns (bytes32) {
        _fetchTokens(token, msg.sender, amount);

        // identify destination chain
        (bytes2 chainType, bytes memory chainReference, bytes memory recipient) = to.parseV1();
        bytes memory destChain = ERC7930.formatV1(chainType, chainReference, "");

        // get details for that bridge: gateway, remote bridge, remote token
        address gateway = getGateway(destChain);
        bytes memory bridge = getRemoteBridge(token, destChain);
        bytes memory remote = getRemoteToken(token, destChain);

        // prepare payload
        bytes memory payload = abi.encode(remote, ERC7930.formatEvmV1(block.chainid, msg.sender), recipient, amount);

        // send crosschain signal
        bytes32 sendId = IERC7786GatewaySource(gateway).sendMessage{value: msg.value}(bridge, payload, attributes);
        emit Sent(token, msg.sender, to, amount);

        return sendId;
    }

    function executeMessage(
        bytes32 receiveId,
        bytes memory sender,
        bytes memory payload,
        bytes[] memory /*attributes*/
    ) public payable virtual returns (bytes4) {
        // prevent duplicate
        require(!_processed.get(uint256(receiveId)), ERC7802BridgeDuplicate());
        _processed.set(uint256(receiveId));

        // parse payload
        (bytes memory local, bytes memory from, bytes memory recipient, uint256 amount) = abi.decode(
            payload,
            (bytes, bytes, bytes, uint256)
        );

        // identify source chain and validate corresponding gateway
        (bytes2 chainType, bytes memory chainReference, ) = from.parseV1();
        bytes memory srcChain = ERC7930.formatV1(chainType, chainReference, "");
        require(msg.sender == getGateway(srcChain), ERC7802BridgeInvalidGateway());

        // identify local token (requested for mint) and validate sender is the correct bridge
        (, address token) = local.parseEvmV1(); // todo: check chainid ?
        require(keccak256(sender) == keccak256(getRemoteBridge(token, srcChain)), ERC7802BridgeInvalidSender()); // todo: use Bytes.equal

        // get recipient
        address to = address(bytes20(recipient));

        // distribute bridged tokens
        _distributeTokens(token, to, amount);
        emit Received(token, from, to, amount);

        return IERC7786Receiver.executeMessage.selector;
    }

    function _fetchTokens(address token, address from, uint256 amount) internal virtual {
        IERC7802(token).crosschainBurn(from, amount);
    }

    function _distributeTokens(address token, address to, uint256 amount) internal virtual {
        IERC7802(token).crosschainMint(to, amount);
    }
}

abstract contract ERC7802BridgeCustody is ERC7802Bridge {
    function _fetchTokens(address token, address from, uint256 amount) internal virtual override {
        SafeERC20.safeTransferFrom(IERC20(token), from, address(this), amount);
    }

    function _distributeTokens(address token, address to, uint256 amount) internal virtual override {
        SafeERC20.safeTransfer(IERC20(token), to, amount);
    }
}
