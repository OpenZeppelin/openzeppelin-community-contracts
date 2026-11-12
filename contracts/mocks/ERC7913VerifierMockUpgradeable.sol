// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC7913SignatureVerifier} from "@openzeppelin/contracts/interfaces/IERC7913.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract ERC7913VerifierMockUpgradeable is Initializable, IERC7913SignatureVerifier {
    // Store valid keys and their corresponding signatures
    mapping(bytes32 => bool) private _validKeys;
    mapping(bytes32 => mapping(bytes32 => bool)) private _validSignatures;

    function __ERC7913VerifierMock_init() internal onlyInitializing {
        __ERC7913VerifierMock_init_unchained();
    }

    function __ERC7913VerifierMock_init_unchained() internal onlyInitializing {
        // For testing purposes, we'll consider a specific key as valid
        bytes32 validKeyHash = keccak256(abi.encodePacked("valid_key"));
        _validKeys[validKeyHash] = true;
    }

    function verify(bytes calldata key, bytes32 /* hash */, bytes calldata signature) external pure returns (bytes4) {
        // For testing purposes, we'll only accept specific key/signature combinations
        if (_isKnownSigner1(key, signature) || _isKnownSigner2(key, signature)) {
            return IERC7913SignatureVerifier.verify.selector;
        }
        return 0xffffffff;
    }

    function _isKnownSigner1(bytes calldata key, bytes calldata signature) internal pure returns (bool) {
        return
            keccak256(key) == keccak256(abi.encodePacked("valid_key_1")) &&
            keccak256(signature) == keccak256(abi.encodePacked("valid_signature_1"));
    }

    function _isKnownSigner2(bytes calldata key, bytes calldata signature) internal pure returns (bool) {
        return
            keccak256(key) == keccak256(abi.encodePacked("valid_key_2")) &&
            keccak256(signature) == keccak256(abi.encodePacked("valid_signature_2"));
    }
}
