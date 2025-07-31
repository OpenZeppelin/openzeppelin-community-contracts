// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {InteroperableAddress} from "@openzeppelin/contracts/utils/draft-InteroperableAddress.sol";
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
    using InteroperableAddress for bytes;
    using Strings for *;

    error InvalidOriginGateway(string axelarSourceChain, string axelarSourceAddress);
    error ReceiverExecutionFailed();

    /**
     * @dev Execution of a cross-chain message.
     *
     * In this function:
     *
     * - `axelarSourceChain` is in the Axelar format. It should not be expected to be a proper ERC-7930 format
     * - `axelarSourceAddress` is the sender of the Axelar message. That should be the remote gateway on the chain
     *   which the message originates from. It is NOT the sender of the ERC-7786 crosschain message.
     *
     * Proper ERC-7930 encoding of the crosschain message sender can be found in the message
     */
    function _execute(
        bytes32 commandId,
        string calldata axelarSourceChain, // chain of the remote gateway - axelar format
        string calldata axelarSourceAddress, // address of the remote gateway
        bytes calldata adapterPayload
    ) internal override {
        // Parse the package
        (bytes memory sender, bytes memory recipient, bytes memory payload) = abi.decode(
            adapterPayload,
            (bytes, bytes, bytes)
        );

        // Axelar to ERC-7930 translation
        bytes memory addr = getRemoteGateway(getErc7930Chain(axelarSourceChain));

        // check message validity
        // - `axelarSourceAddress` is the remote gateway on the origin chain.
        require(
            address(bytes20(addr)).toChecksumHexString().equal(axelarSourceAddress), // TODO non-evm chains?
            InvalidOriginGateway(axelarSourceChain, axelarSourceAddress)
        );

        (, address target) = recipient.parseEvmV1();
        bytes4 result = IERC7786Receiver(target).receiveMessage(commandId, sender, payload);
        require(result == IERC7786Receiver.receiveMessage.selector, ReceiverExecutionFailed());
    }
}
