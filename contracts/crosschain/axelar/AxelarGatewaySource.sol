// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";
import {IGatewaySource} from "../IGatewaySource.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";

abstract contract AxelarGatewaySource is IGatewaySource, AxelarGatewayBase {
    function sendMessage(
        string calldata dstChain, // CAIP-2 chain ID
        string calldata dstAccount, // i.e. address
        bytes calldata payload,
        bytes[] calldata attributes
    ) external payable override returns (bytes32) {
        // TODO: Handle ether (payable)
        // TODO: Validate attributes

        string memory srcCAIP10 = CAIP10.format(msg.sender);
        string memory dstCAIP10 = CAIP10.format(dstChain, dstAccount);

        // Create the package
        bytes memory package = abi.encode(srcCAIP10, dstCAIP10, payload, attributes);

        // Emit event
        emit MessageCreated(0, srcCAIP10, dstCAIP10, payload, attributes);

        // Send the message
        localGateway.callContract(fromCAIP2(dstChain), getRemoteGateway(dstChain), package);

        return 0;
    }
}
