// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IAxelarGateway} from "@axelar-network/axelar-cgp-solidity/interfaces/IAxelarGateway.sol";
import {IGatewayIncomingPassive} from "../IGatewayIncomingPassive.sol";
import {IGatewayIncoming} from "../IGatewayIncoming.sol";
import {IGatewayReceiver} from "../IGatewayReceiver.sol";
import {AxelarCAIP2Equivalence} from "./AxelarCAIP2Equivalence.sol";
import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";

abstract contract AxelarGatewayIncoming is
    AxelarExecutable,
    AxelarCAIP2Equivalence,
    IGatewayIncoming,
    IGatewayIncomingPassive
{
    function validateReceivedMessage(
        bytes32 messageId,
        string calldata srcChain, // CAIP-2 chain ID
        string calldata srcAccount, // i.e. address
        bytes calldata payload,
        bytes calldata attributes
    ) public virtual {
        address dstAccount = CAIP10.toString(msg.sender);
        if (!_isValidReceivedMessage(messageId, srcChain, srcAccount, dstAccount, msg.sender, paylod, attributes)) {
            revert GatewayIncomingPassiveInvalidMessage(messageId);
        }
        _execute(string(fromCAIP2(destChain)), srcAccount, wrappedPayload);
    }

    function _isValidReceivedMessage(
        bytes32 messageId,
        string calldata srcChain, // CAIP-2 chain ID
        string calldata srcAccount, // i.e. address
        string calldata dstAccount,
        bytes calldata paylod,
        bytes calldata attributes
    ) internal returns (bool) {
        bytes wrappedPayload = abi.encode(messageId, dstAccount, payload, attributes);
        return gateway.validateContractCall(messageId, srcChain, srcAccount, keccak256(wrappedPayload));
    }

    function _execute(string calldata srcChain, string calldata srcAccount, bytes calldata wrappedPayload) internal virtual {
        (bytes32 messageId, string destAccount, bytes payload, bytes attributes) = abi.decode(wrappedPayload, (bytes32, string, bytes, bytes));
        IGatewayReceiver(destination).receiveMessage(messageId, srcChain, srcAccount, payload, attributes);
        emit MessageExecuted(messageId);
    }
}
