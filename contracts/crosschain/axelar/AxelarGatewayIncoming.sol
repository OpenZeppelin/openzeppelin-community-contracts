// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IAxelarGateway} from "../vendor/axelar/interfaces/IAxelarGateway.sol";
import {IGatewayIncomingPassive} from "../IGatewayIncomingPassive.sol";
import {IGatewayIncoming} from "../IGatewayIncoming.sol";
import {IGatewayReceiver} from "../IGatewayReceiver.sol";

abstract contract AxelarGatewayIncoming is IGatewayIncoming, IGatewayIncomingPassive, IGatewayReceiver {
    IAxelarGateway public immutable gateway;

    function validateReceivedMessage(
        bytes32 messageId,
        string calldata srcChain, // CAIP-2 chain ID
        string calldata srcAccount, // i.e. address
        bytes calldata payload,
        bytes calldata attributes
    ) public virtual {
        if (!_isValidReceivedMessage(messageId, srcChain, srcAccount, payload, attributes)) {
            revert GatewayIncomingPassiveInvalidMessage(messageId);
        }
    }

    function receiveMessage(
        bytes32 messageId,
        string calldata srcChain,
        string calldata srcAccount,
        bytes calldata payload,
        bytes calldata attributes
    ) external payable override {
        if (msg.sender != address(gateway)) {
            validateReceivedMessage(messageId, srcChain, srcAccount, payload, attributes);
        }
        emit MessageExecuted(messageId);
        _execute(messageId, srcChain, srcAccount, payload, attributes);
    }

    function _isValidReceivedMessage(
        bytes32 messageId,
        string calldata srcChain, // CAIP-2 chain ID
        string calldata srcAccount, // i.e. address
        bytes calldata payload,
        bytes calldata /* attributes */
    ) internal returns (bool) {
        return gateway.validateContractCall(messageId, srcChain, srcAccount, keccak256(payload));
    }

    function _execute(
        bytes32 messageId,
        string calldata srcChain,
        string calldata srcAccount,
        bytes calldata payload,
        bytes calldata attributes
    ) internal virtual;
}
