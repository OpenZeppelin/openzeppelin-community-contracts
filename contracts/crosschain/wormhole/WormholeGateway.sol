// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IGatewaySource} from "../IGatewaySource.sol";
import {IGatewayDestination} from "../IGatewayDestination.sol";
import {IGatewayReceiver} from "../IGatewayReceiver.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";
import {IWormholeRelayer, VaaKey} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import {IWormholeReceiver} from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import {toWormholeFormat} from "wormhole-solidity-sdk/Utils.sol";

function addressFromHexString(string memory hexString) pure returns (address) {
    return address(0); // TODO
}

contract WormholeGatewayBase {
    function currentChain() public view returns (uint16) {}

    function fromCAIP2(string memory caip2) public view returns (uint16) {
        return 0; // TODO
    }

    function getRemoteGateway(string memory caip2) public view returns (string memory remoteGateway) {
        return ""; // TODO
    }
}

// TODO: allow non-evm destination chains via non-evm-specific finalize/retry variants
contract WormholeGatewaySource is IGatewaySource, WormholeGatewayBase {
    IWormholeRelayer public immutable wormholeRelayer;

    struct PendingMessage {
        address sender;
        uint16 dstChain;
        string dstAccount;
        bytes payload;
        bytes[] attributes;
    }

    uint256 nextOutboxId;
    mapping(bytes32 => PendingMessage) private pending;
    mapping(bytes32 => uint64) private sequences;

    constructor(IWormholeRelayer _wormholeRelayer) {
        wormholeRelayer = _wormholeRelayer;
    }

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

        pending[outboxId] = PendingMessage(msg.sender, fromCAIP2(dstChain), dstAccount, payload, attributes);

        string memory caip10Src = CAIP10.format(msg.sender);
        string memory caip10Dst = CAIP10.format(dstChain, dstAccount);
        emit MessageCreated(outboxId, Message(caip10Src, caip10Dst, payload, attributes));
    }

    function finalizeEvmMessage(bytes32 outboxId, uint256 gasLimit) external payable {
        PendingMessage storage pmsg = pending[outboxId];

        require(pmsg.sender != address(0));

        // TODO: fix this, payload needs to be wrapped and sent to adapter gateway
        sequences[outboxId] = wormholeRelayer.sendPayloadToEvm{value: msg.value}(
            pmsg.dstChain,
            addressFromHexString(pmsg.dstAccount),
            pmsg.payload,
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
            VaaKey(currentChain(), toWormholeFormat(pmsg.sender), seq),
            pmsg.dstChain,
            0,
            gasLimit,
            newDeliveryProvider
        );
    }
}

contract WormholeGatewayDestination is WormholeGatewayBase, IGatewayDestination, IWormholeReceiver {
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory additionalMessages,
        bytes32 sourceAddress,
        uint16 sourceChain,
        bytes32 deliveryHash
    ) external payable {
        require(additionalMessages.length == 0); // unsupported
        // TODO
    }
}
