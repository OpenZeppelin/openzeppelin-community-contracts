// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IGatewayDestinationPassive} from "../interfaces/IGatewayDestinationPassive.sol";
import {IGatewayReceiver} from "../interfaces/IGatewayReceiver.sol";

contract GatewayReceiverMock is IGatewayReceiver {
    address public immutable GATEWAY;

    event MessageReceived(bytes gatewayMessageKey, string source, string sender, bytes payload, bytes[] attributes);

    constructor(address _gateway) {
        GATEWAY = _gateway;
    }

    function isGateway(address instance) public view returns (bool) {
        return instance == GATEWAY;
    }

    function receiveMessage(
        address gateway,
        bytes calldata gatewayMessageKey,
        string calldata source,
        string calldata sender,
        bytes calldata payload,
        bytes[] calldata attributes
    ) public payable {
        if (isGateway(msg.sender)) {
            // Active mode
            // no extra check
        } else if (isGateway(gateway)) {
            // Passive mode
            IGatewayDestinationPassive(gateway).validateReceivedMessage(
                gatewayMessageKey,
                source,
                sender,
                payload,
                attributes
            );
        } else {
            revert("invalid call");
        }
        emit MessageReceived(gatewayMessageKey, source, sender, payload, attributes);
    }
}
