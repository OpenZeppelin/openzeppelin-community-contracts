// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IAxelarGateway} from "@axelar-network/axelar-cgp-solidity/interfaces/IAxelarGateway.sol";
import {IGatewayIncomingPassive} from "../IGatewayIncomingPassive.sol";
import {IGatewayIncoming} from "../IGatewayIncoming.sol";
import {IGatewayReceiver} from "../IGatewayReceiver.sol";
import {AxelarCAIP2Equivalence} from "./AxelarCAIP2Equivalence.sol";
import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/executable/AxelarExecutable.sol";

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
        if (!_isValidReceivedMessage(messageId, srcChain, srcAccount, payload, attributes)) {
            revert GatewayIncomingPassiveInvalidMessage(messageId);
        }
        _execute(string(fromCAIP2(destChain)), srcAccount, payload);
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

    function _execute(string calldata srcChain, string calldata srcAccount, bytes calldata payload) internal virtual {
        (address destination, bytes memory data) = abi.decode(payload, (address, bytes));
        IGatewayReceiver(destination).receiveMessage(keccak256(data), sourceChain, sourceAddress, data, "");
        emit MessageExecuted(keccak256(data)); // What to use if we can't reconstruct the message?
    }
}
