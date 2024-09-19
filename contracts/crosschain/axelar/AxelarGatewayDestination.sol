// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {StringsUnreleased} from "../../utils/Strings.sol";
import {CAIP2} from "../../utils/CAIP-2.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";
import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";
import {IGatewayDestinationPassive} from "../interfaces/IGatewayDestinationPassive.sol";
import {IGatewayReceiver} from "../interfaces/IGatewayReceiver.sol";

abstract contract AxelarGatewayDestination is IGatewayDestinationPassive, AxelarGatewayBase, AxelarExecutable {
    using Strings for string;

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
        bytes memory package = abi.encode(
            CAIP10.format(source, sender),
            CAIP10.format(msg.sender),
            payload,
            attributes
        );

        // Check package was received from remote gateway on src chain
        require(
            gateway.validateContractCall(commandId, fromCAIP2(source), getRemoteGateway(source), keccak256(package)),
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
        bytes calldata package
    ) internal virtual override {
        // Parse the package
        (string memory from, string memory to, bytes memory payload, bytes[] memory attributes) = abi.decode(
            package,
            (string, string, bytes, bytes[])
        );

        (string memory source, string memory sender) = CAIP10.parse(from);
        (string memory destination, string memory receiver) = CAIP10.parse(to);

        // check message validity
        // - `remoteChain` matches origin chain in the message (in caip2)
        // - `remoteAccount` is the remote gateway on the origin chain.
        require(remoteChain.equal(fromCAIP2(source)), "Invalid origin chain");
        require(remoteAccount.equal(getRemoteGateway(source)), "Invalid origin gateway");
        // This check is not required for security. That is enforced by axelar (+ source gateway)
        require(destination.equal(CAIP2.format()), "Invalid tardet chain");

        // Active mode
        IGatewayReceiver(StringsUnreleased.parseAddress(receiver)).receiveMessage(
            address(0), // not needed in active mode
            new bytes(0), // not needed in active mode
            source,
            sender,
            payload,
            attributes
        );
    }
}
