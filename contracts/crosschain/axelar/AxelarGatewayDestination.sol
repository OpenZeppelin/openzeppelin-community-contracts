// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AxelarGatewayBase} from "./AxelarGatewayBase.sol";
import {IGatewayDestination} from "../IGatewayDestination.sol";
import {IGatewayDestinationPassive} from "../IGatewayDestinationPassive.sol";
import {IGatewayReceiver} from "../IGatewayReceiver.sol";
import {CAIP2} from "../../utils/CAIP-2.sol";
import {CAIP10} from "../../utils/CAIP-10.sol";

abstract contract AxelarGatewayDestination is
    IGatewayDestination,
    // IGatewayDestinationPassive, // TODO
    AxelarGatewayBase,
    AxelarExecutable
{
    // function validateReceivedMessage(
    //     bytes32 messageDestinationId,
    //     string calldata srcChain, // CAIP-2 chain ID
    //     string calldata srcAccount, // i.e. address
    //     bytes calldata payload,
    //     bytes calldata attributes
    // ) public virtual {
    //     address dstAccount = CAIP10.toString(msg.sender);
    //     if (!_isValidReceivedMessage(messageDestinationId, srcChain, srcAccount, dstAccount, msg.sender, paylod, attributes)) {
    //         revert GatewayDestinationPassiveInvalidMessage(messageDestinationId);
    //     }
    //     _execute(string(fromCAIP2(destChain)), srcAccount, wrappedPayload);
    // }

    // function _isValidReceivedMessage(
    //     bytes32 messageDestinationId,
    //     string calldata srcChain, // CAIP-2 chain ID
    //     string calldata srcAccount, // i.e. address
    //     string calldata dstAccount,
    //     bytes calldata paylod,
    //     bytes calldata attributes
    // ) internal returns (bool) {
    //     bytes wrappedPayload = abi.encode(messageDestinationId, dstAccount, payload, attributes);
    //     return gateway.validateContractCall(messageDestinationId, srcChain, srcAccount, keccak256(wrappedPayload));
    // }

    // In this function:
    // - `srcChain` is in the Axelar format. It should not be expected to be a proper CAIP-2 format
    // - `srcAccount` is the sender of the crosschain message. That should be the foreign gateway on the chain which
    //   the message originates from. It is NOT the sender of the crosschain message
    //
    // Proper CAIP-10 encoding of the message sender (including the CAIP-2 name of the origin chain can be found in
    // the mssage)
    function _execute(
        string calldata srcChain,
        string calldata srcAccount,
        bytes calldata wrappedPayload
    ) internal virtual override {
        // Parse the message package
        // - message identifier (from the source, not unique ?)
        // - source account (caller of this gateway)
        // - destination account
        // - payload
        // - attributes
        (
            bytes32 messageId,
            string memory caip10Src,
            string memory caip10Dst,
            bytes memory payload,
            bytes memory attributes
        ) = abi.decode(wrappedPayload, (bytes32, string, string, bytes, bytes));

        (string memory originChain, string memory originAccount) = CAIP10.parse(caip10Src);
        (string memory targetChain, string memory targetAccount) = CAIP10.parse(caip10Dst);

        // check message validity
        // - `srcChain` matches origin chain in the message (in caip2)
        // - `srcAccount` is the foreign gateway on the origin chain.
        require(Strings.equal(srcChain, fromCAIP2(originChain)), "Invalid origin chain");
        require(Strings.equal(srcAccount, getForeignGateway(originChain)), "Invalid origin gateway");
        require(CAIP2.isCurrentId(targetChain), "Invalid tardet chain");

        // TODO: not available yet
        // address destination = address(uint160(Strings.toUint(targetAccount)));
        targetAccount;
        address destination = address(0);

        IGatewayReceiver(destination).receiveMessage(messageId, originChain, originAccount, payload, attributes);
        emit MessageExecuted(messageId);
    }
}
