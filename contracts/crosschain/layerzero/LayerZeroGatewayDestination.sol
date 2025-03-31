// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ILayerZeroReceiver, Origin} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroReceiver.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC7786Receiver} from "../../interfaces/IERC7786.sol";
import {LayerZeroGatewayBase} from "./LayerZeroGatewayBase.sol";

abstract contract LayerZeroGatewayDestination is LayerZeroGatewayBase, ILayerZeroReceiver {
    using BitMaps for BitMaps.BitMap;
    using Strings for *;

    BitMaps.BitMap private _executed;

    error InvalidOriginGateway(string sourceChain, bytes32 layerZeroSourceAddress);
    error MessageAlreadyExecuted(bytes32 outboxId);
    error ReceiverExecutionFailed();
    error ExtraDataNotSupported();

    function allowInitializePath(Origin calldata _origin) public view virtual returns (bool) {
        return _origin.sender == getRemoteGateway(toCAIP2(_origin.srcEid));
    }

    function nextNonce(uint32 /*_eid*/, bytes32 /*_sender*/) public view virtual returns (uint64) {
        return 0; // No ordering enforced
    }

    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address /*_executor*/, // what is that
        bytes calldata _extraData
    ) public payable virtual onlyLayerZeroEndpoint {
        string memory sourceChain = toCAIP2(_origin.srcEid);

        require(_extraData.length == 0, ExtraDataNotSupported());
        require(getRemoteGateway(sourceChain) == _origin.sender, InvalidOriginGateway(sourceChain, _origin.sender));

        string memory messageId = uint256(_guid).toHexString(32);

        (
            bytes32 outboxId,
            string memory sender,
            string memory receiver,
            bytes memory payload,
            bytes[] memory attributes
        ) = abi.decode(_message, (bytes32, string, string, bytes, bytes[]));

        // prevent replay - deliveryHash might not be unique if a message is relayed multiple time
        require(!_executed.get(uint256(outboxId)), MessageAlreadyExecuted(outboxId));
        _executed.set(uint256(outboxId));

        bytes4 result = IERC7786Receiver(receiver.parseAddress()).executeMessage(
            messageId,
            sourceChain,
            sender,
            payload,
            attributes
        );
        require(result == IERC7786Receiver.executeMessage.selector, ReceiverExecutionFailed());
    }
}
