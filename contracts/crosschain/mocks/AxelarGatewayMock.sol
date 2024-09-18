// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {IAxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarExecutable.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {StringsUnreleased} from "../../utils/Strings.sol";

contract AxelarGatewayActiveMock {
    using Strings for address;

    function callContract(
        string calldata destinationChain,
        string calldata destinationContractAddress,
        bytes calldata payload
    ) external {
        // TODO: check that destination chain is local

        emit IAxelarGateway.ContractCall(
            msg.sender,
            destinationChain,
            destinationContractAddress,
            keccak256(payload),
            payload
        );

        // NOTE:
        // - no commandId in this mock
        // - source chain and destination chain are the same in this mock
        address target = StringsUnreleased.parseAddress(destinationContractAddress);
        IAxelarExecutable(target).execute(bytes32(0), destinationChain, msg.sender.toHexString(), payload);
    }
}

contract AxelarGatewayPassiveMock {
    using Strings for address;
    using BitMaps for BitMaps.BitMap;

    BitMaps.BitMap private pendingCommandIds;

    event NewCommandId(
        bytes32 indexed commandId,
        string destinationChain,
        string destinationContractAddress,
        bytes payload
    );

    function callContract(
        string calldata destinationChain,
        string calldata destinationContractAddress,
        bytes calldata payload
    ) external {
        // TODO: check that destination chain is local

        emit IAxelarGateway.ContractCall(
            msg.sender,
            destinationChain,
            destinationContractAddress,
            keccak256(payload),
            payload
        );

        bytes32 commandId = keccak256(
            abi.encode(destinationChain, msg.sender.toHexString(), destinationContractAddress, keccak256(payload))
        );

        require(!pendingCommandIds.get(uint256(commandId)));
        pendingCommandIds.set(uint256(commandId));

        emit NewCommandId(commandId, destinationChain, destinationContractAddress, payload);
    }

    function validateContractCall(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash
    ) external returns (bool) {
        if (pendingCommandIds.get(uint256(commandId))) {
            pendingCommandIds.unset(uint256(commandId));

            return
                commandId == keccak256(abi.encode(sourceChain, sourceAddress, msg.sender.toHexString(), payloadHash));
        } else return false;
    }
}
