// contracts/MyERC7786GatewaySource.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CAIP2} from "@openzeppelin/contracts/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC7786GatewaySource} from "../../../interfaces/IERC7786.sol";

abstract contract MyERC7786GatewaySource is IERC7786GatewaySource {
    using Strings for address;

    error UnsupportedNativeTransfer();

    /// @inheritdoc IERC7786GatewaySource
    function supportsAttribute(bytes4 /*selector*/) public pure returns (bool) {
        return false;
    }

    /// @inheritdoc IERC7786GatewaySource
    function sendMessage(
        string calldata destinationChain, // CAIP-2 chain identifier
        string calldata receiver, // CAIP-10 account address (does not include the chain identifier)
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable returns (bytes32 outboxId) {
        require(msg.value == 0, UnsupportedNativeTransfer());
        // Use of `if () revert` syntax to avoid accessing attributes[0] if it's empty
        if (attributes.length > 0)
            revert UnsupportedAttribute(attributes[0].length < 0x04 ? bytes4(0) : bytes4(attributes[0][0:4]));

        // Emit event
        outboxId = bytes32(0); // Explicitly set to 0. Can be used for post-processing
        emit MessagePosted(
            outboxId,
            CAIP10.format(CAIP2.local(), msg.sender.toChecksumHexString()),
            CAIP10.format(destinationChain, receiver),
            payload,
            attributes
        );

        // Optionally: If this is an adapter, send the message to a protocol gateway for processing
        // This may require the logic for tracking destination gateway addresses and chain identifiers

        return outboxId;
    }
}
