// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC7786Receiver} from "../../interfaces/IERC7786.sol";

/**
 * @dev Base implementation of an ERC-7786 compliant cross-chain message receiver.
 *
 * This abstract contract exposes the `executeMessage` function that is used for communication with (one or multiple)
 * destination gateways. This contract leaves two functions unimplemented:
 *
 * {_isKnownGateway}, an internal getter used to verify whether an address is recognised by the contract as a valid
 * ERC-7786 destination gateway. One or multiple gateway can be supported. Note that any malicious address for which
 * this function returns true would be able to impersonate any account on any other chain sending any message.
 *
 * {_processMessage}, the internal function that will be called with any message that has been validated.
 */
abstract contract ERC7786Receiver is IERC7786Receiver {
    error ERC7786ReceiverInvalidGateway(address gateway);
    error ERC7786ReceivePassiveModeValue();

    /// @inheritdoc IERC7786Receiver
    function executeMessage(
        string calldata source,
        string calldata sender,
        bytes calldata payload,
        bytes[] calldata attributes
    ) public payable virtual returns (bytes4) {
        require(_isKnownGateway(msg.sender), ERC7786ReceiverInvalidGateway(msg.sender));
        _processMessage(msg.sender, source, sender, payload, attributes);
        return IERC7786Receiver.executeMessage.selector;
    }

    /// @dev Virtual getter that returns whether an address is a valid ERC-7786 gateway.
    function _isKnownGateway(address instance) internal view virtual returns (bool);

    /// @dev Virtual function that should contain the logic to execute when a cross-chain message is received.
    function _processMessage(
        address gateway,
        string calldata sourceChain,
        string calldata sender,
        bytes calldata payload,
        bytes[] calldata attributes
    ) internal virtual;
}
