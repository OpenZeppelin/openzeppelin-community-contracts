// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Origin, MessagingParams, MessagingReceipt, MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroReceiver.sol";

contract LayerZeroEndpointMock {
    uint256 private _seq;
    mapping(address => uint64) private _nonces;

    function send(
        MessagingParams memory params,
        address /*refundAddress*/
    ) external payable returns (MessagingReceipt memory) {
        bytes32 guid = bytes32(++_seq);
        uint64 nonce = ++_nonces[msg.sender];

        ILayerZeroReceiver(address(bytes20(params.receiver << 96))).lzReceive(
            Origin(params.dstEid, bytes32(bytes20(msg.sender)) >> 96, nonce),
            guid,
            params.message,
            address(0), // unused
            bytes("")
        );
        return MessagingReceipt(guid, nonce, MessagingFee(msg.value, 0));
    }
}
