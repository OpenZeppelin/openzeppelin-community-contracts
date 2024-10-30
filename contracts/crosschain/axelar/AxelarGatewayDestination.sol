// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {CAIP2} from "@openzeppelin/contracts@master/utils/CAIP2.sol";
import {CAIP10} from "@openzeppelin/contracts@master/utils/CAIP10.sol";
import {Strings} from "@openzeppelin/contracts@master/utils/Strings.sol";
import {IERC7786GatewayDestinationPassive, IERC7786Receiver} from "../interfaces/draft-IERC7786.sol";
import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";

/**
 * @dev Implementation of an ERC7786 gateway destination adapter for the Axelar Network in dual mode.
 *
 * The contract provides an internal {_execute} function to be used by a child contract (active mode),
 * Alternatively, it provides a way to set a message as executed by calling the {setExecutedMessage}
 * function (passive mode).
 */
abstract contract AxelarGatewayDestination is IERC7786GatewayDestinationPassive, AxelarGatewayBase, AxelarExecutable {
    using Strings for address;
    using Strings for string;

    /// @dev Sets a message as executed so it can't be executed again. Should be called by the receiver contract.
    function setExecutedMessage(
        bytes calldata messageKey,
        string calldata source, // CAIP-2
        string calldata sender, // CAIP-10
        bytes calldata payload,
        bytes[] calldata attributes
    ) external {
        // Extract Axelar commandId
        bytes32 commandId = abi.decode(messageKey, (bytes32));

        // Rebuild expected package
        bytes memory adapterPayload = abi.encode(
            sender,
            msg.sender.toChecksumHexString(), // receiver
            payload,
            attributes
        );

        // Check package was received from remote gateway on src chain
        require(
            gateway.validateContractCall(
                commandId,
                getEquivalentChain(source),
                getRemoteGateway(source),
                keccak256(adapterPayload)
            ),
            NotApprovedByGateway()
        );
    }

    /**
     * @dev Active mode execution of a cross-chain message.
     *
     * In this function:
     *
     * - `remoteChain` is in the Axelar format. It should not be expected to be a proper CAIP-2 format
     * - `remoteAccount` is the sender of the crosschain message. That should be the remote gateway on the chain which
     *   the message originates from. It is NOT the sender of the crosschain message
     *
     * Proper CAIP-10 encoding of the message sender (including the CAIP-2 name of the origin chain) can be found in
     * the message
     */
    function _execute(
        string calldata remoteChain, // chain of the remote gateway - axelar format
        string calldata remoteAccount, // address of the remote gateway
        bytes calldata adapterPayload
    ) internal override {
        // Parse the package
        (string memory sender, string memory receiver, bytes memory payload, bytes[] memory attributes) = abi.decode(
            adapterPayload,
            (string, string, bytes, bytes[])
        );
        string memory source = getEquivalentChain(remoteChain);

        // check message validity
        // - `remoteAccount` is the remote gateway on the origin chain.
        require(getRemoteGateway(source).equal(remoteAccount), "Invalid origin gateway");

        // Active mode
        IERC7786Receiver(receiver.parseAddress()).receiveMessage(
            address(0), // not needed in active mode
            new bytes(0), // not needed in active mode
            source,
            sender,
            payload,
            attributes
        );
    }
}
