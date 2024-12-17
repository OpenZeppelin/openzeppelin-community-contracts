// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC7786Receiver} from "../../interfaces/IERC7786.sol";
import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";

/**
 * @dev Implementation of an ERC-7786 gateway destination adapter for the Axelar Network in dual mode.
 *
 * The contract implements AxelarExecutable's {_execute} function to execute the message, converting Axelar's native
 * workflow into the standard ERC-7786.
 */
abstract contract AxelarGatewayDestination is AxelarGatewayBase, AxelarExecutable {
    using Strings for address;
    using Strings for string;

    error InvalidOriginGateway(string sourceChain, string axelarSourceAddress);
    error ReceiverExecutionFailed();

    /**
     * @dev Execution of a cross-chain message.
     *
     * In this function:
     *
     * - `axelarSourceChain` is in the Axelar format. It should not be expected to be a proper CAIP-2 format
     * - `axelarSourceAddress` is the sender of the Axelar message. That should be the remote gateway on the chain
     *   which the message originates from. It is NOT the sender of the ERC-7786 crosschain message.
     *
     * Proper CAIP-10 encoding of the message sender (including the CAIP-2 name of the origin chain can be found in
     * the message)
     */
    function _execute(
        string calldata axelarSourceChain, // chain of the remote gateway - axelar format
        string calldata axelarSourceAddress, // address of the remote gateway
        bytes calldata adapterPayload
    ) internal override {
        // Parse the package
        (string memory sender, string memory receiver, bytes memory payload, bytes[] memory attributes) = abi.decode(
            adapterPayload,
            (string, string, bytes, bytes[])
        );
        // Axelar to CAIP-2 translation
        string memory sourceChain = getEquivalentChain(axelarSourceChain);

        // check message validity
        // - `axelarSourceAddress` is the remote gateway on the origin chain.
        require(
            getRemoteGateway(sourceChain).equal(axelarSourceAddress),
            InvalidOriginGateway(sourceChain, axelarSourceAddress)
        );

        bytes4 result = IERC7786Receiver(receiver.parseAddress()).executeMessage(
            sourceChain,
            sender,
            payload,
            attributes
        );
        require(result == IERC7786Receiver.executeMessage.selector, ReceiverExecutionFailed());
    }
}
