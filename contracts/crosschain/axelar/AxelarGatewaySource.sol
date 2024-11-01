// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {CAIP2} from "@openzeppelin/contracts@master/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts@master/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts@master/utils/Strings.sol";
import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";
import {IERC7786GatewaySource} from "../interfaces/draft-IERC7786.sol";

/**
 * @dev Implementation of an ERC7786 gateway source adapter for the Axelar Network.
 *
 * The contract provides a way to send messages to a remote chain using the Axelar Network
 * using the {sendMessage} function.
 */
abstract contract AxelarGatewaySource is IERC7786GatewaySource, AxelarGatewayBase {
    using Strings for address;

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 /*selector*/) public pure returns (bool) {
        return false;
    }

    /// @inheritdoc IERC7786GatewaySource
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
        emit MessagePosted(
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
