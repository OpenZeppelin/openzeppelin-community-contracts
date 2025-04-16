// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IWormholeReceiver} from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC7786Receiver} from "../../interfaces/IERC7786.sol";
import {WormholeGatewayBase} from "./WormholeGatewayBase.sol";

abstract contract WormholeGatewayDestination is WormholeGatewayBase, IWormholeReceiver {
    using BitMaps for BitMaps.BitMap;
    using Strings for *;

    BitMaps.BitMap private _executed;

    error InvalidOriginGateway(string sourceChain, bytes32 wormholeSourceAddress);
    error MessageAlreadyExecuted(bytes32 outboxId);
    error ReceiverExecutionFailed();
    error AdditionalMessagesNotSupported();

    function receiveWormholeMessages(
        bytes memory adapterPayload,
        bytes[] memory additionalMessages,
        bytes32 wormholeSourceAddress,
        uint16 wormholeSourceChain,
        bytes32 deliveryHash
    ) public payable virtual onlyWormholeRelayer {
        string memory sourceChain = toCAIP2(wormholeSourceChain);

        require(additionalMessages.length == 0, AdditionalMessagesNotSupported());
        require(
            getRemoteGateway(sourceChain) == wormholeSourceAddress,
            InvalidOriginGateway(sourceChain, wormholeSourceAddress)
        );

        (
            bytes32 outboxId,
            string memory sender,
            string memory receiver,
            bytes memory payload,
            bytes[] memory attributes
        ) = abi.decode(adapterPayload, (bytes32, string, string, bytes, bytes[]));

        // prevent replay - deliveryHash might not be unique if a message is relayed multiple time
        require(!_executed.get(uint256(outboxId)), MessageAlreadyExecuted(outboxId));
        _executed.set(uint256(outboxId));

        bytes4 result = IERC7786Receiver(receiver.parseAddress()).executeMessage(
            uint256(deliveryHash).toHexString(32),
            sourceChain,
            sender,
            payload,
            attributes
        );
        require(result == IERC7786Receiver.executeMessage.selector, ReceiverExecutionFailed());
    }
}
