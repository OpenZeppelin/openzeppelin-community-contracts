// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";
import {IGatewaySource} from "../IGatewaySource.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";

abstract contract AxelarGatewaySource is IGatewaySource, AxelarGatewayBase {
    function sendMessage(
        string calldata dstChain, // CAIP-2 chain ID
        string calldata dstAccount, // i.e. address
        bytes calldata payload,
        bytes calldata attributes
    ) external payable override returns (bytes32) {
        // TODO: Handle ether (payable)
        // TODO: Validate attributes

        // Validate there's an equivalent chain identifier supported by the gateway
        require(supported(dstChain), UnsupportedChain(dstChain));
        string memory caip10Src = CAIP10.currentId(Strings.toHexString(msg.sender));
        string memory caip10Dst = CAIP10.toString(dstChain, dstAccount);
        string memory axelarDst = fromCAIP2(dstChain);
        string memory foreignGateway = getForeignGateway(dstChain);

        // Create a message package
        // - message identifier (from the source, not unique ?)
        // - source account (caller of this gateway)
        // - destination account
        // - payload
        // - attributes
        bytes32 messageId = bytes32(0); // TODO: counter ?
        bytes memory package = abi.encode(messageId, caip10Src, caip10Dst, payload, attributes);

        // emit event
        emit MessageCreated(messageId, Message(caip10Src, caip10Dst, payload, attributes));

        // Send the message
        localGateway.callContract(axelarDst, foreignGateway, package);

        // TODO
        // emit MessageSent(bytes32(0));

        return messageId;
    }
}
