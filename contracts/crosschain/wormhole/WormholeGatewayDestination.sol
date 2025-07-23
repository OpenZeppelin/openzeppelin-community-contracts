// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IWormholeReceiver} from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";
import {IERC7786Receiver} from "../../interfaces/IERC7786.sol";
import {WormholeGatewayBase} from "./WormholeGatewayBase.sol";

abstract contract WormholeGatewayDestination is WormholeGatewayBase, IWormholeReceiver {
    using BitMaps for BitMaps.BitMap;
    using InteroperableAddress for bytes;

    BitMaps.BitMap private _executed;

    error InvalidOriginGateway(uint16 wormholeSourceChain, bytes32 wormholeSourceAddress);
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
        require(additionalMessages.length == 0, AdditionalMessagesNotSupported());

        (bytes32 outboxId, bytes memory sender, bytes memory recipient, bytes memory payload) = abi.decode(
            adapterPayload,
            (bytes32, bytes, bytes, bytes)
        );

        // Axelar to ERC-7930 translation
        bytes32 addr = getRemoteGateway(getErc7930Chain(wormholeSourceChain));

        // check message validity
        // - `axelarSourceAddress` is the remote gateway on the origin chain.
        require(addr == wormholeSourceAddress, InvalidOriginGateway(wormholeSourceChain, wormholeSourceAddress));

        // prevent replay - deliveryHash might not be unique if a message is relayed multiple time
        require(!_executed.get(uint256(outboxId)), MessageAlreadyExecuted(outboxId));
        _executed.set(uint256(outboxId));

        (, address target) = recipient.parseEvmV1();
        bytes4 result = IERC7786Receiver(target).receiveMessage(deliveryHash, sender, payload);
        require(result == IERC7786Receiver.receiveMessage.selector, ReceiverExecutionFailed());
    }
}
