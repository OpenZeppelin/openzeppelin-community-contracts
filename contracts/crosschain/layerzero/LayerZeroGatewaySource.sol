// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {MessagingParams, MessagingFee} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {CAIP2} from "@openzeppelin/contracts/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {LayerZeroGatewayBase} from "./LayerZeroGatewayBase.sol";
import {IERC7786GatewaySource} from "../../interfaces/IERC7786.sol";

// TODO: allow non-evm destination chains via non-evm-specific finalize/retry variants
abstract contract LayerZeroGatewaySource is IERC7786GatewaySource, LayerZeroGatewayBase {
    using Strings for *;

    struct PendingMessage {
        uint64 sequence;
        address sender;
        string destinationChain;
        string receiver;
        bytes payload;
        bytes[] attributes;
    }

    uint256 private _outboxId;
    mapping(bytes32 => PendingMessage) private _pending;

    event MessagePushed(bytes32 outboxId);
    error InvalidOutboxId(bytes32 outboxId);
    error UnsupportedNativeTransfer();

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 /*selector*/) public pure returns (bool) {
        return false;
    }

    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(
        string calldata destinationChain, // CAIP-2 chain identifier
        string calldata receiver, // CAIP-10 account address (does not include the chain identifier)
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 outboxId) {
        require(msg.value == 0, UnsupportedNativeTransfer());
        // Use of `if () revert` syntax to avoid accessing attributes[0] if it's empty
        if (attributes.length > 0)
            revert UnsupportedAttribute(attributes[0].length < 0x04 ? bytes4(0) : bytes4(attributes[0][0:4]));

        require(supportedChain(destinationChain), UnsupportedChain(destinationChain));

        outboxId = bytes32(++_outboxId);
        _pending[outboxId] = PendingMessage(0, msg.sender, destinationChain, receiver, payload, attributes);

        emit MessagePosted(
            outboxId,
            CAIP10.format(CAIP2.local(), msg.sender.toChecksumHexString()),
            CAIP10.format(destinationChain, receiver),
            payload,
            attributes
        );
    }

    function quote(bytes32 outboxId) external view returns (uint256) {
        PendingMessage storage pmsg = _pending[outboxId];
        require(pmsg.sender != address(0), InvalidOutboxId(outboxId));

        return
            _layerZeroEndpoint
                .quote(
                    MessagingParams({
                        dstEid: fromCAIP2(pmsg.destinationChain),
                        receiver: getRemoteGateway(pmsg.destinationChain),
                        message: abi.encode(
                            outboxId,
                            pmsg.sender.toChecksumHexString(),
                            pmsg.receiver,
                            pmsg.payload,
                            pmsg.attributes
                        ),
                        options: bytes(""),
                        payInLzToken: true
                    }),
                    address(this)
                )
                .nativeFee;
    }

    function finalize(bytes32 outboxId, address refundAddress) external payable {
        PendingMessage storage pmsg = _pending[outboxId];
        require(pmsg.sender != address(0), InvalidOutboxId(outboxId));

        // This returns a MessagingReceipt memory
        _layerZeroEndpoint.send{value: msg.value}(
            MessagingParams({
                dstEid: fromCAIP2(pmsg.destinationChain),
                receiver: getRemoteGateway(pmsg.destinationChain),
                message: abi.encode(
                    outboxId,
                    pmsg.sender.toChecksumHexString(),
                    pmsg.receiver,
                    pmsg.payload,
                    pmsg.attributes
                ),
                options: bytes(""),
                payInLzToken: true
            }),
            refundAddress
        );

        emit MessagePushed(outboxId);
    }
}
