// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";
import {IGatewaySource} from "../interfaces/IGatewaySource.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CAIP2} from "../../utils/CAIP-2.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";

abstract contract AxelarGatewaySource is IGatewaySource, AxelarGatewayBase {
    using Strings for address;

    function supportsAttribute(bytes4 /*selector*/) public view virtual returns (bool) {
        return false;
    }

    function sendMessage(
        string calldata destination, // CAIP-2 chain ID
        string calldata receiver, // i.e. address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable virtual returns (bytes32) {
        // TODO: add support for value and attributes ?
        require(msg.value == 0, "Value not supported");
        for (uint256 i = 0; i < attributes.length; ++i) {
            bytes4 selector = bytes4(attributes[i][0:4]);
            require(supportsAttribute(selector), UnsuportedAttribute(selector));
        }

        // Create the package
        string memory sender = msg.sender.toHexString();
        bytes memory adapterPayload = abi.encode(sender, receiver, payload, attributes);

        // Emit event
        emit MessageCreated(
            0,
            CAIP10.format(CAIP2.local(), sender),
            CAIP10.format(destination, receiver),
            payload,
            attributes
        );

        // Send the message
        string memory axelarDestination = getEquivalentChain(destination);
        string memory remoteGateway = getRemoteGateway(destination);
        localGateway.callContract(axelarDestination, remoteGateway, adapterPayload);

        return 0;
    }
}
