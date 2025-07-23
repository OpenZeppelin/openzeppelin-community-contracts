// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC7786GatewaySource} from "../../interfaces/IERC7786.sol";
import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";

/**
 * @dev Implementation of an ERC-7786 gateway source adapter for the Axelar Network.
 *
 * The contract provides a way to send messages to a remote chain via the Axelar Network
 * using the {sendMessage} function.
 */
abstract contract AxelarGatewaySource is IERC7786GatewaySource, AxelarGatewayBase {
    using InteroperableAddress for bytes;
    using Strings for address;

    error UnsupportedNativeTransfer();

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 /*selector*/) public pure returns (bool) {
        return false;
    }

    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(
        bytes calldata recipient, // Binary Interoperable Address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 sendId) {
        require(msg.value == 0, UnsupportedNativeTransfer());
        // Use of `if () revert` syntax to avoid accessing attributes[0] if it's empty
        if (attributes.length > 0)
            revert UnsupportedAttribute(attributes[0].length < 0x04 ? bytes4(0) : bytes4(attributes[0][0:4]));

        // Create the package
        bytes memory sender = InteroperableAddress.formatEvmV1(block.chainid, msg.sender);
        bytes memory adapterPayload = abi.encode(sender, recipient, payload);

        // Emit event
        sendId = bytes32(0); // Explicitly set to 0
        emit MessageSent(sendId, sender, recipient, payload, 0, attributes);

        // Send the message
        (bytes2 chainType, bytes calldata chainReference, ) = recipient.parseV1Calldata();
        string memory axelarDestination = getAxelarChain(InteroperableAddress.formatV1(chainType, chainReference, ""));
        bytes memory remoteGateway = getRemoteGateway(chainType, chainReference);
        _axelarGateway.callContract(
            axelarDestination,
            address(bytes20(remoteGateway)).toChecksumHexString(), // TODO non-evm chains?
            adapterPayload
        );

        return sendId;
    }
}
