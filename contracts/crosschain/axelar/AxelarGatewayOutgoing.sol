// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IAxelarGateway} from "../vendor/axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "../vendor/axelar/interfaces/IAxelarGasService.sol";
import {IGatewayOutgoing} from "../IGatewayOutgoing.sol";
import {AxelarCAIP2Equivalence} from "./AxelarCAIP2Equivalence.sol";
import {CAIP2} from "../../utils/CAIP-2.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";

abstract contract AxelarGatewayOutgoing is IGatewayOutgoing, AxelarCAIP2Equivalence {
    IAxelarGateway public immutable axelarGateway;

    function sendMessage(
        string calldata destChain, // CAIP-2 chain ID
        string calldata destAccount, // i.e. address
        bytes calldata data,
        bytes calldata attributes
    ) external payable override returns (bytes32 messageId) {
        // TODO: Handle ether (payable)
        // TODO: Validate attributes

        // Validate there's an equivalent chain identifier supported by the gateway
        string memory destinationCAIP2 = CAIP2.toString(destChain);
        if (!supported(destinationCAIP2)) revert UnsupportedChain(destinationCAIP2);

        // Create a message
        Message memory message = Message(
            CAIP10.currentId(Strings.toHexString(msg.sender)),
            CAIP10.toString(destinationCAIP2, destAccount),
            data,
            attributes
        );
        bytes32 id = keccak256(message);
        emit MessageCreated(id, message);

        // Send the message
        axelarGateway.callContract(string(fromCAIP2(destination)), destAccount, data);
        emit MessageSent(id);

        return id;
    }
}
