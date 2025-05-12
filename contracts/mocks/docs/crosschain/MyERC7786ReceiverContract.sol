// contracts/MyERC7786ReceiverContract.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {ERC7786Receiver} from "../../../crosschain/utils/ERC7786Receiver.sol";

contract MyERC7786ReceiverContract is ERC7786Receiver, AccessManaged {
    constructor(address initialAuthority) AccessManaged(initialAuthority) {}

    /// @dev Check if the given instance is a known gateway.
    function _isKnownGateway(address /* instance */) internal view virtual override returns (bool) {
        return true;
    }

    /// @dev Internal endpoint for receiving cross-chain message.
    /// @param sourceChain {CAIP2} chain identifier
    /// @param sender {CAIP10} account address (does not include the chain identifier)
    function _processMessage(
        address gateway,
        string calldata messageId,
        string calldata sourceChain,
        string calldata sender,
        bytes calldata payload,
        bytes[] calldata attributes
    ) internal virtual override restricted {
        // Process the message here
    }
}
