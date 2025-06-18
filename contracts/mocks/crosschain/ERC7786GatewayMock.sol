// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {IERC7786GatewaySource, IERC7786Receiver} from "../../interfaces/IERC7786.sol";
import {ERC7930} from "../../utils/ERC7930.sol";

contract ERC7786GatewayMock is IERC7786GatewaySource {
    using BitMaps for BitMaps.BitMap;
    using ERC7930 for *;

    function supportsAttribute(bytes4 /*selector*/) public pure returns (bool) {
        return false;
    }

    function sendMessage(
        bytes calldata recipient, // Binary Interoperable Address
        bytes calldata payload,
        bytes[] calldata attributes
    ) public payable returns (bytes32) {
        require(msg.value == 0, "Value not supported");
        // Use of `if () revert` syntax to avoid accessing attributes[0] if it's empty
        if (attributes.length > 0) revert UnsupportedAttribute(bytes4(attributes[0][0:4]));

        // TODO
        // require(destination.equal(CAIP2.local()), "This mock only supports local messages");

        bytes memory sender = ERC7930.formatEvmV1(block.chainid, msg.sender);
        (, , bytes calldata target) = recipient.parseV1Calldata();
        require(
            IERC7786Receiver(address(bytes20(target))).executeMessage(bytes32(0), sender, payload, attributes) ==
                IERC7786Receiver.executeMessage.selector,
            "Receiver error"
        );

        emit MessageSent(0, sender, recipient, payload, 0, attributes);
        return 0;
    }
}
