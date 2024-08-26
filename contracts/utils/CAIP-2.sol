// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// chain_id:    namespace + ":" + reference
// namespace:   [-a-z0-9]{3,8}
// reference:   [-_a-zA-Z0-9]{1,32}
library CAIP2 {
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    bytes1 private constant SEMICOLON = ":";
    bytes32 private constant EVM_REFERENCE = bytes32("eip155"); // EIP-155 for EVM chains

    /// @dev Converts a namespace and reference to a CAIP2 chain identifier.
    function toString(bytes8 namespace, bytes32 ref) internal pure returns (string memory) {
        return string(abi.encodePacked(namespace, SEMICOLON, ref));
    }

    /// @dev Parses a CAIP2 identifier from a string by splitting it at the first semicolon.
    /// The function parses both sides as `bytes8` and `bytes32` respectively without any validation.
    function fromString(string memory caip2) internal pure returns (bytes8 namespace, bytes32 ref) {
        bytes memory chainBuffer = bytes(caip2);
        uint8 semicolonIndex = _findSemicolonIndex(chainBuffer);
        return (_extractNamespace(chainBuffer, semicolonIndex), _unsafeExtractReference(chainBuffer, semicolonIndex));
    }

    /// @dev Checks if the given CAIP2 identifier is the current chain.
    function isCurrentId(string memory caip2) internal view returns (bool) {
        (bytes8 namespace, bytes32 ref) = fromString(caip2);
        (bytes8 _namespace, bytes32 _ref) = currentId();
        return namespace == _namespace && ref == _ref;
    }

    /// @dev Returns the CAIP2 identifier of the current chain.
    function currentId() internal view returns (bytes8 namespace, bytes32 ref) {
        return (currentNamespace(), currentReference());
    }

    /// @dev Returns the CAIP2 identifier of the current chain.
    /// Assumes block.chainId < type(uint64).max
    function currentNamespace() internal view returns (bytes8 _chainId) {
        unchecked {
            uint256 id = block.chainid;
            while (true) {
                _chainId = bytes8(uint64(_chainId) - 1);
                assembly ("memory-safe") {
                    mstore8(_chainId, byte(mod(id, 10), HEX_DIGITS))
                }
                id /= 10;
                if (id == 0) break;
            }
        }
    }

    /// @dev Returns the reference of the current chain.
    function currentReference() internal pure returns (bytes32) {
        return EVM_REFERENCE;
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
