// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {IERC7786Recipient} from "@openzeppelin/contracts/interfaces/IERC7786.sol";

/// @dev Returns the correct ERC-7786 magic value followed by a large amount of padding, so a caller that copies
/// the full return buffer runs out of gas on the copy.
contract ERC7786RecipientReturnBombMock is IERC7786Recipient {
    function receiveMessage(bytes32, bytes calldata, bytes calldata) external payable returns (bytes4) {
        assembly ("memory-safe") {
            // First 32 bytes: ABI-encoded `IERC7786Recipient.receiveMessage.selector`.
            mstore(0x00, shl(224, 0x2432ef26))
            // Pay for a 1 MiB return buffer.
            mstore(0x0ffffc, 0)
            return(0x00, 0x100000)
        }
    }
}
