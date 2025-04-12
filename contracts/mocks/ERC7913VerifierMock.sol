// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC7913SignatureVerifier} from "../../contracts/interfaces/IERC7913.sol";

contract ERC7913VerifierMock is IERC7913SignatureVerifier {
    // Store valid keys and their corresponding signatures
    mapping(bytes32 => bool) private _validKeys;
    mapping(bytes32 => mapping(bytes32 => bool)) private _validSignatures;

    constructor() {
        // For testing purposes, we'll consider a specific key as valid
        bytes32 validKeyHash = keccak256(abi.encodePacked("valid_key"));
        _validKeys[validKeyHash] = true;
    }

    function verify(bytes calldata key, bytes32 /* hash */, bytes calldata signature) external pure returns (bytes4) {
        // For testing purposes, we'll only accept a specific key and signature combination
        if (
            keccak256(key) == keccak256(abi.encodePacked("valid_key")) &&
            keccak256(signature) == keccak256(abi.encodePacked("valid_signature"))
        ) {
            return IERC7913SignatureVerifier.verify.selector;
        }
        return 0xffffffff;
    }
}
