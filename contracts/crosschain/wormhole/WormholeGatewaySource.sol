// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {VaaKey} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import {toUniversalAddress} from "wormhole-solidity-sdk/utils/UniversalAddress.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {WormholeGatewayBase} from "./WormholeGatewayBase.sol";
import {IERC7786GatewaySource} from "../../interfaces/IERC7786.sol";

// TODO: allow non-evm destination chains via non-evm-specific finalize/retry variants
abstract contract WormholeGatewaySource is IERC7786GatewaySource, WormholeGatewayBase {
    using InteroperableAddress for bytes;
    // using Strings for *;

    struct PendingMessage {
        bool pending;
        address sender;
        uint256 value;
        bytes recipient;
        bytes payload;
    }

    uint256 private _sendId;
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
        bytes calldata recipient, // Binary Interoperable Address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 sendId) {
        // Use of `if () revert` syntax to avoid accessing attributes[0] if it's empty
        if (attributes.length > 0)
            revert UnsupportedAttribute(attributes[0].length < 0x04 ? bytes4(0) : bytes4(attributes[0][0:4]));

        // Note: this reverts with UnsupportedChainId if the recipient is not on a supported chain.
        // No real need to check the return value.
        getRemoteGateway(recipient);

        sendId = bytes32(++_sendId);
        _pending[sendId] = PendingMessage(true, msg.sender, msg.value, recipient, payload);

        emit MessageSent(
            sendId,
            InteroperableAddress.formatEvmV1(block.chainid, msg.sender),
            recipient,
            payload,
            0,
            attributes
        );
    }

    function quoteRelay(
        bytes calldata recipient, // Binary Interoperable Address
        bytes calldata /*payload*/,
        bytes[] calldata /*attributes*/,
        uint256 value,
        uint256 gasLimit,
        address /*refundRecipient*/
    ) external view returns (uint256) {
        (uint256 cost, ) = _wormholeRelayer.quoteEVMDeliveryPrice(getWormholeChain(recipient), value, gasLimit);
        return cost - value;
    }

    function requestRelay(bytes32 sendId, uint256 gasLimit, address /*refundRecipient*/) external payable {
        // TODO: revert if refundRecipient is not address(0)?

        PendingMessage storage pmsg = _pending[sendId];

        require(pmsg.pending, CannotFinalizeMessage(sendId));
        pmsg.pending = false;

        // TODO: Do we care about the returned "sequence"?
        // slither-disable-next-line reentrancy-no-eth
        _wormholeRelayer.sendPayloadToEvm{value: pmsg.value + msg.value}(
            getWormholeChain(pmsg.recipient),
            getRemoteGateway(pmsg.recipient),
            abi.encode(
                sendId,
                InteroperableAddress.formatEvmV1(block.chainid, pmsg.sender),
                pmsg.recipient,
                pmsg.payload
            ),
            pmsg.value,
            gasLimit
        );

        // Do we want to do that to get a gas refund? Would it be valuable to keep that information stored?
        delete _pending[sendId];
    }
}
