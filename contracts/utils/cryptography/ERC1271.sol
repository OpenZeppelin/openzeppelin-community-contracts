// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {AbstractSigner} from "./AbstractSigner.sol";

/**
 * @dev Simple implementation of {IERC1271} using an underlying {AbstractSigner}.
 */
abstract contract ERC1271 is AbstractSigner, IERC1271 {
    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 hash, bytes calldata signature) public view virtual override returns (bytes4) {
        return _isValidSignature(hash, signature) ? IERC1271.isValidSignature.selector : bytes4(0xffffffff);
    }

    function _isValidSignature(bytes32 hash, bytes calldata signature) internal view virtual returns (bool) {
        return _rawSignatureValidation(hash, signature);
    }
}
