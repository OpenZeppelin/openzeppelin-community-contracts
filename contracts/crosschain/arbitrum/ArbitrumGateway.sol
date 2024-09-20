// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IInbox} from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";
import {ArbSys} from "@arbitrum/nitro-contracts/src/precompiles/ArbSys.sol";
import {IGatewaySource} from "../IGatewaySource.sol";
import {IGatewayDestination} from "../IGatewayDestination.sol";
import {IGatewayReceiver} from "../IGatewayReceiver.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

string constant CHAINID_ETH = "eip155:1";
string constant CHAINID_ARB = "eip155:42161";

function addressFromHexString(string memory hexString) pure returns (address) {
    return address(0); // TODO
}

interface IArbitrumGatewayL2Destination {
    function deliverMessage(address sender, address receiver, bytes calldata payload) external;
}

contract ArbitrumGatewayL1Source is IGatewaySource {
    IInbox private _inbox; // TODO
    address private _remoteGateway;

    struct PendingMessage {
        address sender;
        address receiver;
        uint256 value;
        bytes payload;
    }

    uint256 private _nextOutboxId;
    mapping(bytes32 outboxId => PendingMessage) private _pending;

    function sendMessage(
        string calldata destChain,
        string calldata destAccount,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable override returns (bytes32 outboxId) {
        require(Strings.equal(destChain, CHAINID_ARB));
        require(attributes.length == 0);

        address receiver = addressFromHexString(destAccount);
        require(receiver != address(0));

        outboxId = bytes32(_nextOutboxId++);
        _pending[outboxId] = PendingMessage(msg.sender, receiver, msg.value, payload);
    }

    function finalizeMessage(
        bytes32 outboxId,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas
    ) external payable {
        PendingMessage storage pmsg = _pending[outboxId];

        require(pmsg.receiver != address(0));

        bytes memory adapterPayload = abi.encodeCall(
            IArbitrumGatewayL2Destination.deliverMessage,
            (pmsg.sender, pmsg.receiver, pmsg.payload)
        );

        _inbox.createRetryableTicket{value: msg.value + pmsg.value}(
            _remoteGateway,
            pmsg.value,
            maxSubmissionCost,
            excessFeeRefundAddress,
            callValueRefundAddress,
            gasLimit,
            maxFeePerGas,
            adapterPayload
        );

        delete pmsg.receiver;
        delete pmsg.value;
        delete pmsg.payload;
    }
}

contract ArbitrumGatewayL1Destination is IGatewayDestination, IArbitrumGatewayL2Destination {
    using Strings for address;

    ArbSys private _arbSys; // TODO
    address private _remoteGateway;

    function deliverMessage(address sender, address receiver, bytes calldata payload) external {
        require(_arbSys.wasMyCallersAddressAliased());
        require(_arbSys.myCallersAddressWithoutAliasing() == _remoteGateway);

        IGatewayReceiver(receiver).receiveMessage(0, CHAINID_ETH, sender.toHexString(), payload, new bytes[](0));
    }
}

contract ArbitrumGatewayL2Source is IGatewaySource {
    using Strings for address;

    ArbSys private _arbSys; // TODO
    address private _remoteGateway;

    function sendMessage(
        string calldata destChain,
        string calldata destAccount,
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable override returns (bytes32) {
        require(Strings.equal(destChain, CHAINID_ETH));
        require(attributes.length == 0);

        address receiver = addressFromHexString(destAccount);

        bytes memory receiveMessage = abi.encodeCall(
            IGatewayReceiver.receiveMessage,
            (0, CHAINID_ARB, msg.sender.toHexString(), payload, new bytes[](0))
        );

        _arbSys.sendTxToL1(receiver, receiveMessage);

        return 0;
    }
}
