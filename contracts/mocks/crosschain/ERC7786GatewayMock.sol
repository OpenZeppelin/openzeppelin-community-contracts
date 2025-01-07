// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CAIP2} from "@openzeppelin/contracts/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {IERC7786GatewaySource, IERC7786Receiver} from "../../interfaces/IERC7786.sol";

contract ERC7786GatewayMock is IERC7786GatewaySource {
    using BitMaps for BitMaps.BitMap;
    using Strings for *;

    function supportsAttribute(bytes4 /*selector*/) public pure returns (bool) {
        return false;
    }

    function sendMessage(
        string calldata destination, // CAIP-2 chain ID
        string calldata receiver, // CAIP-10 account ID
        bytes calldata payload,
        bytes[] calldata attributes
    ) public payable returns (bytes32) {
        require(msg.value == 0, "Value not supported");
        // Use of `if () revert` syntax to avoid accessing attributes[0] if it's empty
        if (attributes.length > 0) revert UnsupportedAttribute(bytes4(attributes[0][0:4]));
        require(destination.equal(CAIP2.local()), "This mock only supports local messages");

        string memory source = destination;
        string memory sender = msg.sender.toChecksumHexString();

        address target = Strings.parseAddress(receiver);
        require(
            IERC7786Receiver(target).executeMessage(source, sender, payload, attributes) ==
                IERC7786Receiver.executeMessage.selector,
            "Receiver error"
        );

        emit MessagePosted(0, CAIP10.format(source, sender), CAIP10.format(source, receiver), payload, attributes);
        return 0;
    }
}
