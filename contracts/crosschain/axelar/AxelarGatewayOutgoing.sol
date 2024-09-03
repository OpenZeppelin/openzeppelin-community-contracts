// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IAxelarGateway} from "@axelar-network/axelar-cgp-solidity/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "@axelar-network/axelar-cgp-solidity/interfaces/IAxelarGasService.sol";
import {IGatewayOutgoing} from "../IGatewayOutgoing.sol";
import {AxelarCAIP2Equivalence} from "./AxelarCAIP2Equivalence.sol";
import {CAIP2} from "../../utils/CAIP-2.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";

abstract contract AxelarGatewayOutgoing is IGatewayOutgoing, AxelarCAIP2Equivalence {
    IAxelarGateway public immutable gateway;

    function sendMessage(
        string calldata destChain, // CAIP-2 chain ID
        string calldata destAccount, // i.e. address
        bytes calldata payload,
        bytes calldata attributes
    ) external payable override returns (bytes32 messageId) {
        // TODO: Handle ether (payable)
        // TODO: Validate attributes

        // Validate there's an equivalent chain identifier supported by the gateway
        if (!supported(destChain)) revert UnsupportedChain(destChain);

        // Create a message
        Message memory message = Message(
            CAIP10.currentId(Strings.toHexString(msg.sender)),
            CAIP10.toString(destChain, destAccount),
            payload,
            attributes
        );
        messageId = keccak256(abi.encode(message));
        emit MessageCreated(id, message);

        // Wrap the message
        bytes wrappedPayload = abi.encode(messageId, destAccount, payload, attributes);

        // Send the message
        address destGateway = address(0); // TODO
        gateway.callContract(string(fromCAIP2(destChain)), destGateway, wrappedPayload);
        emit MessageSent(messageId);
    }
}
