// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IAxelarGateway} from "./vendor/axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "./vendor/axelar/interfaces/IAxelarGasService.sol";

import {GatewaySource} from "./Gateway.sol";
import {GatewayAxelarCAIP2} from "./GatewayAxelarCAIP2.sol";
import {CAIP10} from "../utils/CAIP-10.sol";

contract GatewayAxelar is GatewaySource, GatewayAxelarCAIP2 {
    IAxelarGateway public immutable axelarGateway;
    IAxelarGasService public immutable gasService;

    error UnsupportedNativeCurrency();

    constructor(IAxelarGateway _axelarGateway, address _initialOwner) Ownable(_initialOwner) {
        axelarGateway = _axelarGateway;
    }

    function _authorizeCreatingMessage(
        string memory source,
        Message memory message
    ) internal override returns (bytes32) {
        if (message.value > 0) {
            revert UnsupportedNativeCurrency();
        }

        if (!isRegisteredCAIP2(CAIP10.fromString(destination)._chainId)) {
            revert UnsupportedChain(chain);
        }

        return super._authorizeCreatingMessage(source, message);
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
            gateway.callContract(details.name, details.remote, payload);
        }

        return id;
    }
}
