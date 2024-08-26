// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IAxelarGateway} from "../vendor/axelar/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "../vendor/axelar/interfaces/IAxelarGasService.sol";
import {IGatewayOutgoing} from "../IGatewayOutgoing.sol";
import {AxelarCAIP2Equivalence} from "./AxelarCAIP2Equivalence.sol";
import {CAIP2} from "../../utils/CAIP-2.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";

abstract contract AxelarGatewayOutgoing is IGatewayOutgoing, AxelarCAIP2Equivalence {
    IAxelarGateway public immutable axelarGateway;

    function sendMessage(
        string calldata destChain, // CAIP-2 chain ID
        string calldata destAccount, // i.e. address
        bytes calldata payload,
        bytes calldata /* attributes */
    ) external payable override returns (bytes32 messageId) {
        // TODO: Handle ether (payable)
        if (!supported(destChain)) revert UnsupportedChain(destChain);
        axelarGateway.callContract(string(fromCAIP2(destChain)), destAccount, payload);
        return keccak256(payload);
    }
}
