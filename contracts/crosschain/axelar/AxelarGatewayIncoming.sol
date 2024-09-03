// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IAxelarGateway} from "@axelar-network/axelar-cgp-solidity/interfaces/IAxelarGateway.sol";
import {IGatewayIncomingPassive} from "../IGatewayIncomingPassive.sol";
import {IGatewayIncoming} from "../IGatewayIncoming.sol";

abstract contract AxelarGatewayIncoming is IGatewayIncoming, IGatewayIncomingPassive {
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
        emit MessageExecuted(messageId);
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
    ) internal {
        // messageId
    }
}
