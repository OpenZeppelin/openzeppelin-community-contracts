// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {CAIP10} from "../../utils/CAIP-10.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GatewaySource} from "../GatewaySource.sol";
import {Set} from "../../utils/Set.sol";

contract GatewaySourceGeneric is GatewaySource, Ownable {
    using Set for Set.Bytes32Set;
    using CAIP10 for CAIP10.Account;

    Set.Bytes32Set private _createdBox;
    Set.Bytes32Set private _sentBox;

    constructor() Ownable(msg.sender) {}

    /// @inheritdoc GatewaySource
    function messageId(
        string memory source,
        string memory destination,
        Message memory message
    ) public pure override returns (bytes32) {
        return keccak256(abi.encode(source, destination, message));
    }

    /// @inheritdoc GatewaySource
    function sendingStatus(bytes32 id) public view virtual override returns (MessageSourceStatus) {
        if (_sentBox.contains(id)) return MessageSourceStatus.Sent;
        if (_createdBox.contains(id)) return MessageSourceStatus.Created;
        return MessageSourceStatus.Unknown;
    }

    /// @inheritdoc GatewaySource
    function _authorizeMessageForwarded(
        string memory destination,
        Message memory message
    ) internal virtual override onlyOwner {}

    /// @inheritdoc GatewaySource
    function _createMessage(
        bytes32 id,
        MessageSourceStatus,
        Message memory
    ) internal virtual override returns (bytes32) {
        _createdBox.insert(id);
        return id;
    }

    /// @inheritdoc GatewaySource
    function _sendMessage(bytes32 id, MessageSourceStatus, Message memory) internal virtual override returns (bytes32) {
        _sentBox.insert(id);
        return id;
    }
}
