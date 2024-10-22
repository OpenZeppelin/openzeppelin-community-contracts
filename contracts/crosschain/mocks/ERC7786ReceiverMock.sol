// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC7786Receiver} from "../vendor/draft-ERC7786Receiver.sol";

contract ERC7786ReceiverMock is ERC7786Receiver {
    address public immutable GATEWAY;

    event MessageReceived(address gateway, string source, string sender, bytes payload, bytes[] attributes);

    constructor(address _gateway) {
        GATEWAY = _gateway;
    }

    function _isKnownGateway(address instance) internal view virtual override returns (bool) {
        return instance == GATEWAY;
    }

    function _processMessage(
        address gateway,
        string calldata source,
        string calldata sender,
        bytes calldata payload,
        bytes[] calldata attributes
    ) internal virtual override {
        emit MessageReceived(gateway, source, sender, payload, attributes);
    }
}
