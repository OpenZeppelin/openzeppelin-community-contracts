// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @dev Equivalence interface between CAIP-2 chain identifiers and protocol-specific chain identifiers.
///
/// See https://chainagnostic.org/CAIPs/caip-2[CAIP2].
interface ICAIP2Equivalence {
    error UnsupportedChain(string caip2);

    /// @dev Checks if a CAIP-2 chain identifier is registered as equivalent to a protocol-specific chain identifier.
    function supported(string memory caip2) external view returns (bool);

    /// @dev Retrieves the protocol-specific chain identifier equivalent to a CAIP-2 chain identifier.
    function fromCAIP2(string memory caip2) external view returns (string memory);
}
