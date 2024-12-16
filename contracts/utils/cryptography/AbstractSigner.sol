// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

abstract contract AbstractSigner {
    /**
     * @dev Signature validation algorithm.
     *
     * WARNING: Implementing a signature validation algorithm is a security-sensitive operation as it involves
     * cryptographic verification. It is important to review and test thoroughly before deployment. Consider
     * using one of the signature verification libraries ({ECDSA}, {P256} or {RSA}).
     */
    function _rawSignatureValidation(bytes32 hash, bytes calldata signature) internal view virtual returns (bool);
}
