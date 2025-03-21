// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {VaaKey} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol"; // VaaKey
import {toUniversalAddress, fromUniversalAddress} from "wormhole-solidity-sdk/utils/UniversalAddress.sol";
import {CAIP2} from "@openzeppelin/contracts/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {WormholeGatewayBase} from "./WormholeGatewayBase.sol";
import {IERC7786GatewaySource} from "../../interfaces/IERC7786.sol";

// TODO: allow non-evm destination chains via non-evm-specific finalize/retry variants
abstract contract WormholeGatewaySource is IERC7786GatewaySource, WormholeGatewayBase {
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
    error CannotFinalizeMessage(bytes32 outboxId);
    error CannotRetryMessage(bytes32 outboxId);
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

    function finalizeEvmMessage(bytes32 outboxId, uint256 gasLimit) external payable {
        PendingMessage storage pmsg = _pending[outboxId];

        require(pmsg.sender != address(0), CannotFinalizeMessage(outboxId));

        uint16 wormholeDestination = fromCAIP2(pmsg.destinationChain);
        bytes32 remoteGateway = getRemoteGateway(pmsg.destinationChain);
        string memory sender = pmsg.sender.toChecksumHexString();
        bytes memory adapterPayload = abi.encode(outboxId, sender, pmsg.receiver, pmsg.payload, pmsg.attributes);

        // TODO: potentially delete part/all of the message

        pmsg.sequence = _wormholeRelayer.sendPayloadToEvm{value: msg.value}(
            wormholeDestination,
            fromUniversalAddress(remoteGateway),
            adapterPayload,
            0,
            gasLimit
        );

        emit MessagePushed(outboxId);
    }

    function retryEvmMessage(bytes32 outboxId, uint256 gasLimit, address newDeliveryProvider) external {
        PendingMessage storage pmsg = _pending[outboxId];

        require(pmsg.sequence != 0, CannotRetryMessage(outboxId));

        pmsg.sequence = _wormholeRelayer.resendToEvm(
            VaaKey(_currentChain, toUniversalAddress(address(this)), pmsg.sequence),
            fromCAIP2(pmsg.destinationChain),
            0,
            gasLimit,
            newDeliveryProvider
        );
    }
}
