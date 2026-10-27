// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @dev Claim holder interface from https://github.com/ethereum/EIPs/issues/735[ERC-735], restricted to the
 * getter that ERC-3643 identity verification relies on.
 *
 * A claim is identified by `keccak256(abi.encode(issuer, topic))`, so a holder keeps at most one claim per
 * issuer and topic.
 */
interface IERC735 {
    /**
     * @dev Returns the claim identified by `claimId`. Returns empty values when the holder has no such claim.
     */
    function getClaim(
        bytes32 claimId
    )
        external
        view
        returns (
            uint256 topic,
            uint256 scheme,
            address issuer,
            bytes memory signature,
            bytes memory data,
            string memory uri
        );
}

/**
 * @dev Interface of an ERC-735 claim issuer that can confirm whether a claim it signed is still valid.
 */
interface IERC735ClaimIssuer {
    /**
     * @dev Returns whether `signature` is a valid signature of this issuer over the claim with `topic` and `data`
     * held by `identity`, and the claim has not been revoked.
     */
    function isClaimValid(
        address identity,
        uint256 topic,
        bytes calldata signature,
        bytes calldata data
    ) external view returns (bool);
}
