// contracts/MyERC7786GatewaySource.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC7786GatewaySource} from "../../../interfaces/IERC7786.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";

abstract contract MyERC7786GatewaySource is IERC7786GatewaySource {
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

        // Emit event
        sendId = bytes32(0); // Explicitly set to 0. Can be used for post-processing
        emit MessageSent(
            sendId,
            InteroperableAddress.formatEvmV1(block.chainid, msg.sender),
            recipient,
            payload,
            0,
            attributes
        );

        // Optionally: If this is an adapter, send the message to a protocol gateway for processing
        // This may require the logic for tracking destination gateway addresses and chain identifiers

        return sendId;
    }
}
