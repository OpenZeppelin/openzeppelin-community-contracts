// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";
import {IGatewaySource} from "../interfaces/IGatewaySource.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";

abstract contract AxelarGatewaySource is IGatewaySource, AxelarGatewayBase {
    function supportsAttribute(bytes4 /*signature*/) public view virtual returns (bool) {
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
            bytes4 signature = bytes4(attributes[i][0:4]);
            require(supportsAttribute(signature), UnsuportedAttribute(signature));
        }

        string memory from = CAIP10.format(msg.sender);
        string memory to = CAIP10.format(destination, receiver);

        // Create the package
        bytes memory package = abi.encode(from, to, payload, attributes);

        // Emit event
        emit MessageCreated(0, from, to, payload, attributes);

        // Send the message
        localGateway.callContract(fromCAIP2(destination), getRemoteGateway(destination), package);

        return 0;
    }
}
