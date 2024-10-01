// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {StringsUnreleased} from "../../utils/Strings.sol";
import {CAIP2} from "../../utils/CAIP-2.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";
import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";
import {IGatewayDestinationPassive} from "../interfaces/IGatewayDestinationPassive.sol";
import {IGatewayReceiver} from "../interfaces/IGatewayReceiver.sol";

abstract contract AxelarGatewayDestination is IGatewayDestinationPassive, AxelarGatewayBase, AxelarExecutable {
    using StringsUnreleased for address;
    using StringsUnreleased for string;

    /// @dev Passive mode
    function validateReceivedMessage(
        bytes calldata messageKey,
        string calldata source, // CAIP-2
        string calldata sender, // CAIP-10
        bytes calldata payload,
        bytes[] calldata attributes
    ) external virtual {
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

    /// @dev Active mode
    // In this function:
    // - `remoteChain` is in the Axelar format. It should not be expected to be a proper CAIP-2 format
    // - `remoteAccount` is the sender of the crosschain message. That should be the remote gateway on the chain which
    //   the message originates from. It is NOT the sender of the crosschain message
    //
    // Proper CAIP-10 encoding of the message sender (including the CAIP-2 name of the origin chain can be found in
    // the message)
    function _execute(
        string calldata remoteChain, // chain of the remote gateway - axelar format
        string calldata remoteAccount, // address of the remote gateway
        bytes calldata adapterPayload
    ) internal virtual override {
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
        IGatewayReceiver(receiver.parseAddress()).receiveMessage(
            address(0), // not needed in active mode
            new bytes(0), // not needed in active mode
            source,
            sender,
            payload,
            attributes
        );
    }
}
