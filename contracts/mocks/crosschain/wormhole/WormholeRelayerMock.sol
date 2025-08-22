// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IWormholeRelayer} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import {IWormholeReceiver} from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import {toUniversalAddress} from "wormhole-solidity-sdk/utils/UniversalAddress.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract WormholeRelayerMock {
    uint16 internal immutable _localChainId;
    uint64 private _seq;

    constructor(uint16 localChainId) {
        _localChainId = localChainId;
    }

    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit,
        uint16 refundChain,
        address refundAddress
    ) public payable returns (uint64) {
        require(targetChain == _localChainId, "This mock only support same-chain message passing");
        require(refundChain == _localChainId, "This mock only support same-chain message passing");
        require(receiverValue <= msg.value, "This mock only support same-chain message passing");

        uint64 seq = _seq++;
        IWormholeReceiver(targetAddress).receiveWormholeMessages{value: receiverValue, gas: gasLimit}(
            payload,
            new bytes[](0),
            toUniversalAddress(msg.sender),
            _localChainId,
            keccak256(abi.encode(seq)) // Unrealistic value but sufficient for current tests
        );

        if (msg.value > receiverValue) {
            Address.sendValue(payable(refundAddress), msg.value - receiverValue);
        }

        return seq;
    }

    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit
    ) public payable returns (uint64) {
        return
            sendPayloadToEvm(targetChain, targetAddress, payload, receiverValue, gasLimit, _localChainId, address(0));
    }
}
