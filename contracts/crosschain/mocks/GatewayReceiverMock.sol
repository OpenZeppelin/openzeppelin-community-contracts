// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IGatewayDestinationPassive} from "../IGatewayDestinationPassive.sol";
import {IGatewayReceiver} from "../IGatewayReceiver.sol";

contract GatewayReceiverMock is IGatewayReceiver {
    address public immutable GATEWAY;

    event MessageReceived(bytes gatewayData, string srcChain, string srcAccount, bytes payload, bytes[] attributes);

    constructor(address _gateway) {
        GATEWAY = _gateway;
    }

    function isGateway(address instance) public view returns (bool) {
        return instance == GATEWAY;
    }

    function receiveMessage(
        address gatewayAddr,
        bytes calldata gatewayData,
        string calldata srcChain,
        string calldata srcAccount,
        bytes calldata payload,
        bytes[] calldata attributes
    ) public payable {
        if (isGateway(msg.sender)) {
            // Active mode
            // no extra check
        } else if (isGateway(gatewayAddr)) {
            // Passive mode
            IGatewayDestinationPassive(gatewayAddr).validateReceivedMessage(
                gatewayData,
                srcChain,
                srcAccount,
                payload,
                attributes
            );
        } else {
            revert("invalid call");
        }
        emit MessageReceived(gatewayData, srcChain, srcAccount, payload, attributes);
    }
}
