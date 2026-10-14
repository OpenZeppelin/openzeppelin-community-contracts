// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

// Interfaces
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC7802} from "@openzeppelin/contracts/interfaces/draft-IERC7802.sol";
import {IERC7786GatewaySource, IERC7786Receiver} from "../interfaces/IERC7786.sol";

// Utilities
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Bytes} from "@openzeppelin/contracts/utils/Bytes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";
import {IndirectCall} from "../utils/IndirectCall.sol";

abstract contract ERC7802Bridge is ERC721("ERC7802Bridge", "ERC7802Bridge"), IERC7786Receiver {
    using BitMaps for BitMaps.BitMap;
    using InteroperableAddress for bytes;

    struct BridgeMetadata {
        address token;
        bool isPaused;
        bool isCustodial;
        mapping(bytes chain => address) gateway;
        mapping(bytes chain => bytes) remote;
    }

    mapping(bytes32 bridgeId => BridgeMetadata) private _bridges;
    BitMaps.BitMap private _processed;

    event Sent(address token, address from, bytes to, uint256 amount);
    event Received(address token, bytes from, address to, uint256 amount);
    event BridgePaused(bytes32 indexed bridgeId, bool isPaused);
    event BridgeLinkSet(bytes32 indexed bridgeId, address gateway, bytes remote);

    error ERC7802BridgePaused(bytes32 bridgeId);
    error ERC7802BridgeInvalidBidgeId(bytes32 bridgeId);
    error ERC7802BridgeMissingGateway(bytes32 bridgeId, bytes chain);
    error ERC7802BridgeMissingRemote(bytes32 bridgeId, bytes chain);
    error ERC7802BridgeDuplicate();
    error ERC7802BridgeInvalidGateway();
    error ERC7802BridgeInvalidSender();

    modifier bridgeAdminRestricted(bytes32 bridgeId) {
        _checkAuthorized(ownerOf(uint256(bridgeId)), msg.sender, uint256(bridgeId));
        _;
    }

    // ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
    // │                                                   Getters                                                   │
    // └─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
    function getBridgeEndpoint(bytes32 bridgeId) public returns (address) {
        return IndirectCall.getRelayer(bridgeId);
    }

    function getBridgeToken(bytes32 bridgeId) public view returns (address token, bool isCustodial) {
        _requireOwned(uint256(bridgeId));
        return (_bridges[bridgeId].token, _bridges[bridgeId].isCustodial);
    }

    function getBridgeGateway(bytes32 bridgeId, bytes memory chain) public view returns (address) {
        _requireOwned(uint256(bridgeId));
        return _bridges[bridgeId].gateway[chain];
    }

    function getBridgeRemote(bytes32 bridgeId, bytes memory chain) public view returns (bytes memory) {
        _requireOwned(uint256(bridgeId));
        return _bridges[bridgeId].remote[chain];
    }

    // ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
    // │                                              Bridge management                                              │
    // └─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

    function setPaused(bytes32 bridgeId, bool isPaused) public bridgeAdminRestricted(bridgeId) {
        _setPaused(bridgeId, isPaused);
    }

    function updateGateway(
        bytes32 bridgeId,
        bytes memory chain,
        address gateway,
        bytes memory remote
    ) public virtual bridgeAdminRestricted(bridgeId) {
        _setGateway(bridgeId, chain, gateway, remote);
    }

    function _setBridge(bytes32 bridgeId, address token, address admin, bool isCustodial) internal {
        _safeMint(admin == address(0) ? address(1) : admin, uint256(bridgeId));
        _bridges[bridgeId].token = token;
        _bridges[bridgeId].isCustodial = isCustodial;
    }

    function _setGateway(bytes32 bridgeId, bytes memory chain, address gateway, bytes memory remote) internal {
        _bridges[bridgeId].gateway[chain] = gateway;
        _bridges[bridgeId].remote[chain] = remote;
        emit BridgeLinkSet(bridgeId, gateway, remote);
    }

    function _setPaused(bytes32 bridgeId, bool isPaused) internal {
        _bridges[bridgeId].isPaused = isPaused;
        emit BridgePaused(bridgeId, isPaused);
    }

    // ┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
    // │                                            Send / Receive tokens                                            │
    // └─────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
    function send(
        bytes32 bridgeId,
        bytes memory to,
        uint256 amount,
        bytes[] memory attributes
    ) public payable virtual returns (bytes32) {
        _requireOwned(uint256(bridgeId));

        require(!_bridges[bridgeId].isPaused, ERC7802BridgePaused(bridgeId));

        address token = _fetchTokens(bridgeId, msg.sender, amount);

        // identify destination chain
        (bytes2 chainType, bytes memory chainReference, bytes memory recipient) = to.parseV1();
        bytes memory destChain = InteroperableAddress.formatV1(chainType, chainReference, "");

        // get details for that bridge: gateway, remote bridge, remote token
        address gateway = _bridges[bridgeId].gateway[destChain];
        bytes memory bridge = _bridges[bridgeId].remote[destChain];

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

    function receiveMessage(
        bytes32 receiveId,
        bytes memory sender,
        bytes memory payload
    ) public payable virtual returns (bytes4) {
        // prevent duplicate
        require(!_processed.get(uint256(receiveId)), ERC7802BridgeDuplicate());
        _processed.set(uint256(receiveId));

        // parse payload
        (bytes32 bridgeId, bytes memory from, bytes memory recipient, uint256 amount) = abi.decode(
            payload,
            (bytes32, bytes, bytes, uint256)
        );

        _requireOwned(uint256(bridgeId));

        // identify source chain and validate corresponding gateway
        (bytes2 chainType, bytes memory chainReference, ) = from.parseV1();
        bytes memory srcChain = InteroperableAddress.formatV1(chainType, chainReference, "");

        require(msg.sender == _bridges[bridgeId].gateway[srcChain], ERC7802BridgeInvalidGateway());
        require(Bytes.equal(sender, _bridges[bridgeId].remote[srcChain]), ERC7802BridgeInvalidSender());

        // get recipient
        address to = address(bytes20(recipient));

        // distribute bridged tokens
        address token = _distributeTokens(bridgeId, to, amount);
        emit Received(token, from, to, amount);

        return IERC7786Receiver.receiveMessage.selector;
    }

    function _fetchTokens(bytes32 bridgeId, address from, uint256 amount) private returns (address) {
        address token = _bridges[bridgeId].token;
        if (_bridges[bridgeId].isCustodial) {
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

    function _distributeTokens(bytes32 bridgeId, address to, uint256 amount) private returns (address) {
        address token = _bridges[bridgeId].token;
        if (_bridges[bridgeId].isCustodial) {
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

contract ERC7802BridgeLinks is ERC7802Bridge {
    function createBridge(address token, bool isCustodial, bytes32 salt) public returns (bytes32) {
        bytes32 bridgeId = keccak256(abi.encodePacked(msg.sender, salt));

        _setBridge(bridgeId, token, msg.sender, isCustodial);

        return bridgeId;
    }
}

contract ERC7802BridgeCounterfactual is ERC7802Bridge {
    using InteroperableAddress for bytes;

    struct Foreign {
        bytes32 id;
        address gateway;
        bytes remote;
    }

    function createBridge(
        address token,
        address admin,
        bool isCustodial,
        Foreign[] calldata foreign
    ) public returns (bytes32) {
        bytes32 bridgeId = _counterfactualBridgeId(
            token,
            bytes32(bytes20(admin)) | bytes32(SafeCast.toUint(isCustodial)),
            foreign
        );

        _setBridge(bridgeId, token, admin, isCustodial);
        for (uint256 i = 0; i < foreign.length; ++i) {
            (bytes2 chainType, bytes memory chainReference, ) = foreign[i].remote.parseV1Calldata();
            bytes memory chain = InteroperableAddress.formatV1(chainType, chainReference, "");
            _setGateway(bridgeId, chain, foreign[i].gateway, foreign[i].remote);
        }

        return bridgeId;
    }

    function updateGateway(
        bytes32 bridgeId,
        bytes memory chain,
        address gateway,
        bytes memory remote
    ) public virtual override {
        require(gateway != address(0) && remote.length > 0);
        // super call is bridgeAdminRestricted(bridgeId)
        super.updateGateway(bridgeId, chain, gateway, remote);
    }

    function _counterfactualBridgeId(
        address token,
        bytes32 opts,
        Foreign[] calldata foreign
    ) private view returns (bytes32) {
        bytes32[] memory ids = new bytes32[](foreign.length + 1);
        bytes32[] memory links = new bytes32[](foreign.length);
        for (uint256 i = 0; i < foreign.length; ++i) {
            require(foreign[i].gateway != address(0) && foreign[i].remote.length > 0);
            ids[i] = foreign[i].id;
            links[i] = keccak256(
                abi.encode(InteroperableAddress.formatEvmV1(block.chainid, foreign[i].gateway), foreign[i].remote)
            );
        }
        ids[foreign.length] = keccak256(
            abi.encode(InteroperableAddress.formatEvmV1(block.chainid, token), opts, Arrays.sort(links))
        );

        return keccak256(abi.encodePacked(Arrays.sort(ids)));
    }
}
