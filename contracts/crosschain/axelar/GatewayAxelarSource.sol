// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IAxelarGateway} from "../vendor/axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "../vendor/axelar/interfaces/IAxelarGasService.sol";

import {GatewaySource} from "../GatewaySource.sol";
import {GatewayAxelarCAIP2} from "./GatewayAxelarCAIP2.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";

contract GatewayAxelarSource is GatewaySource, GatewayAxelarCAIP2 {
    IAxelarGateway public immutable axelarGateway;
    IAxelarGasService public immutable gasService;

    constructor(IAxelarGateway _axelarGateway, address _initialOwner) Ownable(_initialOwner) {
        axelarGateway = _axelarGateway;
    }

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
        if (axelarGateway.isCommandExecuted(commandId)) return MessageDestinationStatus.Executed;
        if (_deliveredBox.contains(id)) return MessageDestinationStatus.Delivered;
        return MessageDestinationStatus.Unknown;
    }

    function _authorizeMessageCreated(
        string memory source,
        Message memory message
    ) internal override returns (bytes32) {
        if (!isRegisteredCAIP2(CAIP10.fromString(destination)._chainId)) {
            revert UnsupportedChain(chain);
        }

        return super._authorizeMessageCreated(source, message);
    }

    function _sendMessage(
        bytes32 id,
        string memory /* source */,
        string memory destination,
        MessageSourceStatus status,
        Message memory message
    ) internal override returns (bytes32) {
        super._sendMessage(id, status, message);

        if (status != MessageSourceStatus.Sent) {
            AxelarChain memory details = chainDetails[CAIP10.fromString(destination)._chainId];
            axelarGateway.callContract(details.name, details.remote, payload);
        }

        return id;
    }
}
