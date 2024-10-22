// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {CAIP2} from "@openzeppelin/contracts@master/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts@master/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts@master/utils/Strings.sol";
import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";
import {IERC7786GatewaySource} from "../interfaces/draft-IERC7786.sol";

abstract contract AxelarGatewaySource is IERC7786GatewaySource, AxelarGatewayBase {
    using Strings for address;

    function supportsAttribute(bytes4 /*selector*/) public pure returns (bool) {
        return false;
    }

    function sendMessage(
        string calldata destination, // CAIP-2 chain ID
        string calldata receiver, // i.e. address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32) {
        require(msg.value == 0, "Value not supported");
        if (attributes.length > 0) revert UnsupportedAttribute(bytes4(attributes[0][0:4]));

        // Create the package
        string memory sender = msg.sender.toChecksumHexString();
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
