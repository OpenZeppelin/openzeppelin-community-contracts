// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IGatewaySource} from "../IGatewaySource.sol";
import {IGatewayDestination} from "../IGatewayDestination.sol";
import {IGatewayReceiver} from "../IGatewayReceiver.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";
import {IWormholeRelayer, VaaKey} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import {IWormholeReceiver} from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import {toWormholeFormat, fromWormholeFormat} from "wormhole-solidity-sdk/Utils.sol";

function addressFromHexString(string memory hexString) pure returns (address) {
    return address(0); // TODO
}

abstract contract WormholeGatewayBase is Ownable {
    event RegisteredRemoteGateway(string caip2, bytes32 remoteGateway);
    event RegisteredCAIP2Equivalence(string caip2, uint16 wormholeId);

    IWormholeRelayer public immutable wormholeRelayer;
    uint16 public immutable currentChain;

    mapping(string caip2 => bytes32 remoteGateway) private _remoteGateways;
    mapping(string caip2 => uint32 wormholeId) private _equivalence;
    mapping(uint16 wormholeId => string caip2) private _equivalence2;

    constructor(IWormholeRelayer _wormholeRelayer, uint16 _currentChain) {
        wormholeRelayer = _wormholeRelayer;
        currentChain = _currentChain;
    }

    function supportedChain(string memory caip2) public view returns (bool) {
        return (_equivalence[caip2] & (1 << 16)) != 0;
    }

    function fromCAIP2(string memory caip2) public view returns (uint16) {
        return uint16(_equivalence[caip2]);
    }

    function toCAIP2(uint16 wormholeId) public view returns (string memory) {
        return _equivalence2[wormholeId];
    }

    function getRemoteGateway(string memory caip2) public view returns (bytes32) {
        return _remoteGateways[caip2];
    }

    function registerCAIP2Equivalence(string calldata caip2, uint16 wormholeId) public onlyOwner {
        require(_equivalence[caip2] == 0);
        _equivalence[caip2] = wormholeId | (1 << 16);
        _equivalence2[wormholeId] = caip2;
        emit RegisteredCAIP2Equivalence(caip2, wormholeId);
    }

    function registerRemoteGateway(string calldata caip2, bytes32 remoteGateway) public onlyOwner {
        require(_remoteGateways[caip2] == 0);
        _remoteGateways[caip2] = remoteGateway;
        emit RegisteredRemoteGateway(caip2, remoteGateway);
    }
}

// TODO: allow non-evm destination chains via non-evm-specific finalize/retry variants
abstract contract WormholeGatewaySource is IGatewaySource, WormholeGatewayBase {
    struct PendingMessage {
        address sender;
        string dstChain;
        string dstAccount;
        bytes payload;
        bytes[] attributes;
    }

    uint256 nextOutboxId;
    mapping(bytes32 => PendingMessage) private pending;
    mapping(bytes32 => uint64) private sequences;

    function supportsAttribute(string calldata) public view returns (bool) {
        return false;
    }

    function sendMessage(
        string calldata dstChain,
        string calldata dstAccount,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable override returns (bytes32 outboxId) {
        require(msg.value == 0);
        require(attributes.length == 0); // no attributes currently supported

        outboxId = bytes32(nextOutboxId++);

        require(supportedChain(dstChain));
        pending[outboxId] = PendingMessage(msg.sender, dstChain, dstAccount, payload, attributes);

        string memory caip10Src = CAIP10.format(msg.sender);
        string memory caip10Dst = CAIP10.format(dstChain, dstAccount);
        emit MessageCreated(outboxId, Message(caip10Src, caip10Dst, payload, attributes));
    }

    function finalizeEvmMessage(bytes32 outboxId, uint256 gasLimit) external payable {
        PendingMessage storage pmsg = pending[outboxId];

        require(pmsg.sender != address(0));

        bytes memory adapterPayload = abi.encode(pmsg.sender, addressFromHexString(pmsg.dstAccount), pmsg.payload);

        sequences[outboxId] = wormholeRelayer.sendPayloadToEvm{value: msg.value}(
            fromCAIP2(pmsg.dstChain),
            fromWormholeFormat(getRemoteGateway(pmsg.dstChain)),
            adapterPayload,
            0,
            gasLimit
        );

        delete pmsg.dstAccount;
        delete pmsg.payload;
        delete pmsg.attributes;
    }

    function retryEvmMessage(bytes32 outboxId, uint256 gasLimit, address newDeliveryProvider) external {
        uint64 seq = sequences[outboxId];

        require(seq != 0);

        PendingMessage storage pmsg = pending[outboxId];

        // TODO: check if new sequence number needs to be stored for future retries
        wormholeRelayer.resendToEvm(
            VaaKey(currentChain, toWormholeFormat(pmsg.sender), seq),
            fromCAIP2(pmsg.dstChain),
            0,
            gasLimit,
            newDeliveryProvider
        );
    }
}

abstract contract WormholeGatewayDestination is WormholeGatewayBase, IGatewayDestination, IWormholeReceiver {
    using Strings for address;

    function receiveWormholeMessages(
        bytes memory adapterPayload,
        bytes[] memory additionalMessages,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
        string memory sourceChainCAIP2 = toCAIP2(sourceChain);

        require(sourceAddress == getRemoteGateway(sourceChainCAIP2));
        require(additionalMessages.length == 0); // unsupported

        (address sender, IGatewayReceiver destination, bytes memory payload) = abi.decode(
            adapterPayload,
            (address, IGatewayReceiver, bytes)
        );
        destination.receiveMessage(deliveryHash, sourceChainCAIP2, sender.toHexString(), payload, new bytes[](0));
    }
}
