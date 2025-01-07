// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {IAxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarExecutable.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract AxelarGatewayMock {
    using Strings for address;
    using Strings for string;
    using BitMaps for BitMaps.BitMap;

    BitMaps.BitMap private _pendingCommandIds;

    event CommandIdPending(
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
            abi.encode(
                destinationChain,
                msg.sender.toChecksumHexString(),
                destinationContractAddress,
                keccak256(payload)
            )
        );

        require(!_pendingCommandIds.get(uint256(commandId)));
        _pendingCommandIds.set(uint256(commandId));

        emit CommandIdPending(commandId, destinationChain, destinationContractAddress, payload);

        // NOTE: source chain and destination chain are the same in this mock
        address target = destinationContractAddress.parseAddress();
        IAxelarExecutable(target).execute(commandId, destinationChain, msg.sender.toChecksumHexString(), payload);
    }

    function validateContractCall(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash
    ) external returns (bool) {
        if (_pendingCommandIds.get(uint256(commandId))) {
            _pendingCommandIds.unset(uint256(commandId));

            emit IAxelarGateway.ContractCallExecuted(commandId);

            return
                commandId ==
                keccak256(abi.encode(sourceChain, sourceAddress, msg.sender.toChecksumHexString(), payloadHash));
        } else return false;
    }
}
