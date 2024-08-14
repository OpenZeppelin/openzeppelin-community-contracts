// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {CAIP10} from "../../utils/CAIP-10.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GatewayDestination} from "../GatewayDestination.sol";
import {Set} from "../../utils/Set.sol";

contract GatewayDestinationGeneric is GatewayDestination, Ownable {
    using Set for Set.Bytes32Set;
    Set.Bytes32Set private _executedBox;
    Set.Bytes32Set private _deliveredBox;

    constructor() Ownable(msg.sender) {}

    /// @inheritdoc GatewayDestination
    function messageId(
        string memory source,
        string memory destination,
        Message memory message
    ) public pure override returns (bytes32) {
        return keccak256(abi.encode(source, destination, message));
    }

    /// @inheritdoc GatewayDestination
    function destinationStatus(bytes32 id) public view override returns (MessageDestinationStatus) {
        if (_executedBox.contains(id)) return MessageDestinationStatus.Executed;
        if (_deliveredBox.contains(id)) return MessageDestinationStatus.Delivered;
        return MessageDestinationStatus.Unknown;
    }

    /// @inheritdoc GatewayDestination
    function _authorizeMessageDelivered(
        string memory destination,
        Message memory message
    ) internal virtual override onlyOwner {}

    /// @inheritdoc GatewayDestination
    function _deliverMessage(
        bytes32 id,
        MessageDestinationStatus,
        Message memory
    ) internal virtual override returns (bytes32) {
        _deliveredBox.insert(id); // Idempotent
        return id;
    }

    /// @inheritdoc GatewayDestination
    function _setMessageExecuted(
        bytes32 id,
        MessageDestinationStatus,
        Message memory
    ) internal virtual override returns (bytes32) {
        _executedBox.insert(id); // Idempotent
        return id;
    }
}
