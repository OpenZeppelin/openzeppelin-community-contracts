// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

library CAIP2 {
    // chain_id:    namespace + ":" + reference
    // namespace:   [-a-z0-9]{3,8}
    // reference:   [-_a-zA-Z0-9]{1,32}
    struct ChainId {
        bytes8 _namespace;
        bytes32 _reference;
    }

    bytes1 constant SEMICOLON = ":";

    error TooLongChainId();

    function toString(ChainId memory chainId) internal pure returns (string memory) {
        return string(abi.encodePacked(chainId._namespace, SEMICOLON, chainId._reference));
    }

    /// @dev Parses a chain ID from a string by splitting it at the first semicolon.
    /// The function parses both sides as `bytes8` and `bytes32` respectively wiothout any validation.
    function fromString(string memory chainStr) internal pure returns (ChainId memory chainId) {
        bytes memory chainBuffer = bytes(chainStr);
        uint8 semicolonIndex = _findSemicolonIndex(chainBuffer);
        chainId._namespace = _extractNamespace(chainBuffer, semicolonIndex);
        chainId._reference = _unsafeExtractReference(chainBuffer, semicolonIndex);
        return chainId;
    }

    /// @dev Extracts the first `semicolonIndex` bytes from the chain buffer as a bytes8 namespace.
    function _extractNamespace(bytes memory chainBuffer, uint8 semicolonIndex) private pure returns (bytes8 namespace) {
        assembly ("memory-safe") {
            let shift := sub(256, mul(semicolonIndex, 8))
            namespace := shl(shift, shr(shift, mload(add(chainBuffer, 0x20))))
        }
    }

    /// @dev Extracts the reference from the chain buffer after the semicolon located at `offset`.
    ///
    /// IMPORTANT: The caller must make sure that the semicolon index is within the chain buffer length
    /// and that there are 32 bytes available after the semicolon. Otherwise dirty memory could be read.
    function _unsafeExtractReference(bytes memory chainBuffer, uint8 offset) private pure returns (bytes32 ref) {
        assembly ("memory-safe") {
            ref := mload(add(chainBuffer, add(0x20, offset)))
        }
    }

    /// @dev Looks for the first semicolon in the chain buffer. This is the optimal way since
    /// the namespace is shorter than the reference.
    function _findSemicolonIndex(bytes memory chainBuffer) private pure returns (uint8) {
        uint8 length = SafeCast.toUint8(chainBuffer.length);
        for (uint8 i = 0; i < length; i++) {
            if (chainBuffer[i] == SEMICOLON) {
                return i;
            }
        }
        return length;
    }
}
