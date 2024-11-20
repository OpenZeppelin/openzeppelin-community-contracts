// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CAIP2} from "@openzeppelin/contracts/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts/utils/CAIP10.sol";
import {IERC7786GatewaySource, IERC7786GatewayDestinationPassive, IERC7786Receiver} from "../interfaces/draft-IERC7786.sol";

contract ERC7786GatewayMock is IERC7786GatewaySource, IERC7786GatewayDestinationPassive {
    using BitMaps for BitMaps.BitMap;
    using Strings for *;

    BitMaps.BitMap private _outbox;
    bool private _activeMode;

    function _setActive(bool newActiveMode) internal {
        _activeMode = newActiveMode;
    }

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
        if (attributes.length > 0) revert UnsupportedAttribute(bytes4(attributes[0][0:4]));
        require(destination.equal(CAIP2.local()), "This mock only supports local messages");

        string memory source = destination;
        string memory sender = msg.sender.toChecksumHexString();

        if (_activeMode) {
            address target = Strings.parseAddress(receiver);
            require(
                IERC7786Receiver(target).executeMessage(
                    address(this),
                    new bytes(0),
                    source,
                    sender,
                    payload,
                    attributes
                ) == IERC7786Receiver.executeMessage.selector,
                "Receiver error"
            );
        } else {
            _outbox.set(uint256(keccak256(abi.encode(source, sender, receiver, payload, attributes))));
        }

        emit MessagePosted(0, CAIP10.format(source, sender), CAIP10.format(source, receiver), payload, attributes);
        return 0;
    }

    function setMessageExecuted(
        bytes calldata /*messageKey*/, // this mock doesn't use a messageKey
        string calldata source,
        string calldata sender,
        bytes calldata payload,
        bytes[] calldata attributes
    ) public {
        uint256 digest = uint256(
            keccak256(abi.encode(source, sender, msg.sender.toChecksumHexString(), payload, attributes))
        );
        require(_outbox.get(digest), "invalid message");
        _outbox.unset(digest);
    }
}
