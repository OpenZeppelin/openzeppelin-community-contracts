// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

// Interfaces
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC7802} from "@openzeppelin/contracts/interfaces/draft-IERC7802.sol";
import {IERC7786GatewaySource, IERC7786Receiver} from "../interfaces/IERC7786.sol";

// Utilities
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";
import {IndirectCall} from "../utils/IndirectCall.sol";

contract ERC7802Bridge is IERC7786Receiver {
    using BitMaps for BitMaps.BitMap;
    using InteroperableAddress for bytes;

    struct BridgeMetadata {
        address token;
        bool isCustodial;
        mapping(bytes chain => address) gateway;
        mapping(bytes chain => bytes) remote;
    }

    mapping(bytes32 bridgeId => BridgeMetadata) private _bridges;
    BitMaps.BitMap private _processed;

    event Sent(address token, address from, bytes to, uint256 amount);
    event Received(address token, bytes from, address to, uint256 amount);

    // event GatewayRegistered(address indexed gateway, bytes chain);
    // event RemoteBridgeRegistered(address indexed token, bytes chain);

    error ERC7802BridgeInvalidBidgeId(bytes32 bridgeId);
    error ERC7802BridgeMissingGateway(bytes32 bridgeId, bytes chain);
    error ERC7802BridgeMissingRemote(bytes32 bridgeId, bytes chain);
    // error ERC7802BridgeImproperChainIdentifier(bytes chain);
    error ERC7802BridgeDuplicate();
    error ERC7802BridgeInvalidGateway();
    error ERC7802BridgeInvalidSender();

    function getBridgeEndpoint(bytes32 bridgeId) public returns (address) {
        return IndirectCall.getRelayer(bridgeId);
    }

    function getBridgeToken(bytes32 bridgeId) public view returns (address token, bool isCustodial) {
        token = _bridges[bridgeId].token;
        isCustodial = _bridges[bridgeId].isCustodial;
        if (token == address(0)) revert ERC7802BridgeInvalidBidgeId(bridgeId);
    }

    function getBridgeGateway(bytes32 bridgeId, bytes memory chain) public view returns (address) {
        address result = _bridges[bridgeId].gateway[chain];
        if (result == address(0)) revert ERC7802BridgeMissingGateway(bridgeId, chain);
        return result;
    }

    function getBridgeRemote(bytes32 bridgeId, bytes memory chain) public view returns (bytes memory) {
        bytes memory result = _bridges[bridgeId].remote[chain];
        if (result.length == 0) revert ERC7802BridgeMissingRemote(bridgeId, chain);
        return result;
    }

    struct Foreign {
        bytes32 id;
        address gateway;
        bytes remote;
    }
    function createBridge(address token, bool isCustodial, Foreign[] calldata foreign) public returns (bytes32) {
        bytes32[] memory ids = new bytes32[](foreign.length + 1);
        bytes32[] memory links = new bytes32[](foreign.length);
        for (uint256 i = 0; i < foreign.length; ++i) {
            ids[i] = foreign[i].id;
            links[i] = keccak256(
                abi.encode(InteroperableAddress.formatEvmV1(block.chainid, foreign[i].gateway), foreign[i].remote)
            );
        }
        ids[foreign.length] = keccak256(
            abi.encode(
                InteroperableAddress.formatEvmV1(block.chainid, token), // bytes token
                bytes32(SafeCast.toUint(isCustodial)), // bytes32 tokenOptions
                Arrays.sort(links)
            )
        );

        bytes32 bridgeId = keccak256(abi.encode(Arrays.sort(ids)));

        // Should we check for collision. I don't think that is necessary
        BridgeMetadata storage details = _bridges[bridgeId];
        details.token = token;
        details.isCustodial = isCustodial;

        for (uint256 i = 0; i < foreign.length; ++i) {
            (bytes2 chainType, bytes memory chainReference, ) = foreign[i].remote.parseV1();
            bytes memory chain = InteroperableAddress.formatV1(chainType, chainReference, "");
            details.gateway[chain] = foreign[i].gateway;
            details.remote[chain] = foreign[i].remote;
        }

        return bridgeId;
    }

    function send(
        bytes32 bridgeId,
        bytes memory to,
        uint256 amount,
        bytes[] memory attributes
    ) public payable virtual returns (bytes32) {
        address token = _fetchTokens(bridgeId, msg.sender, amount);

        // identify destination chain
        (bytes2 chainType, bytes memory chainReference, bytes memory recipient) = to.parseV1();
        bytes memory destChain = InteroperableAddress.formatV1(chainType, chainReference, "");

        // get details for that bridge: gateway, remote bridge, remote token
        address gateway = getBridgeGateway(bridgeId, destChain);
        bytes memory bridge = getBridgeRemote(bridgeId, destChain);

        // prepare payload
        bytes memory payload = abi.encode(
            bridgeId,
            InteroperableAddress.formatEvmV1(block.chainid, msg.sender),
            recipient,
            amount
        );

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
        (bytes32 bridgeId, bytes memory from, bytes memory recipient, uint256 amount) = abi.decode(
            payload,
            (bytes32, bytes, bytes, uint256)
        );

        // identify source chain and validate corresponding gateway
        (bytes2 chainType, bytes memory chainReference, ) = from.parseV1();
        bytes memory srcChain = InteroperableAddress.formatV1(chainType, chainReference, "");

        require(msg.sender == getBridgeGateway(bridgeId, srcChain), ERC7802BridgeInvalidGateway());
        require(Bytes.equal(sender, getBridgeRemote(bridgeId, srcChain)), ERC7802BridgeInvalidSender());

        // get recipient
        address to = address(bytes20(recipient));

        // distribute bridged tokens
        address token = _distributeTokens(bridgeId, to, amount);
        emit Received(token, from, to, amount);

        return IERC7786Receiver.executeMessage.selector;
    }

    function _fetchTokens(bytes32 bridgeId, address from, uint256 amount) internal virtual returns (address) {
        (address token, bool isCustodial) = getBridgeToken(bridgeId);
        if (isCustodial) {
            (bool success, bytes memory returndata) = IndirectCall.indirectCall(
                token,
                abi.encodeCall(IERC20.transferFrom, (from, getBridgeEndpoint(bridgeId), amount)),
                bridgeId
            );
            require(success && (returndata.length == 0 ? token.code.length == 0 : uint256(bytes32(returndata)) == 1));
        } else {
            (bool success, ) = IndirectCall.indirectCall(
                token,
                abi.encodeCall(IERC7802.crosschainBurn, (from, amount)),
                bridgeId
            );
            require(success);
        }
        return token;
    }

    function _distributeTokens(bytes32 bridgeId, address to, uint256 amount) internal virtual returns (address) {
        (address token, bool isCustodial) = getBridgeToken(bridgeId);
        if (isCustodial) {
            (bool success, bytes memory returndata) = IndirectCall.indirectCall(
                token,
                abi.encodeCall(IERC20.transfer, (to, amount)),
                bridgeId
            );
            require(success && (returndata.length == 0 ? token.code.length == 0 : uint256(bytes32(returndata)) == 1));
        } else {
            (bool success, ) = IndirectCall.indirectCall(
                token,
                abi.encodeCall(IERC7802.crosschainMint, (to, amount)),
                bridgeId
            );
            require(success);
        }
        return token;
    }
}
