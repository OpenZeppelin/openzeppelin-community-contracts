// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {IAxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarExecutable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {StringsUnreleased} from "../../utils/Strings.sol";

contract AxelarGatewayMock {
    using Strings for address;

    function callContract(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload
    ) external {
        // TODO: check that destination chain is local

        emit IAxelarGateway.ContractCall(msg.sender, destinationChain, contractAddress, keccak256(payload), payload);

        address target = StringsUnreleased.parseAddress(contractAddress);

        // NOTE:
        // - no commandId in this mock
        // - source chain and destination chain are the same in this mock
        IAxelarExecutable(target).execute(bytes32(0), destinationChain, msg.sender.toHexString(), payload);
    }
}
