// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IWormholeRelayer} from "wormhole-solidity-sdk/interfaces/IWormholeRelayer.sol";
import {IWormholeReceiver} from "wormhole-solidity-sdk/interfaces/IWormholeReceiver.sol";
import {toUniversalAddress} from "wormhole-solidity-sdk/utils/UniversalAddress.sol";

contract WormholeRelayerMock {
    uint64 private _seq;

    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit
    ) external payable returns (uint64) {
        // TODO: check that destination chain is local

        uint64 seq = _seq++;
        IWormholeReceiver(targetAddress).receiveWormholeMessages{value: receiverValue, gas: gasLimit}(
            payload,
            new bytes[](0),
            toUniversalAddress(msg.sender),
            targetChain,
            keccak256(abi.encode(seq))
        );

        return seq;
    }
}
