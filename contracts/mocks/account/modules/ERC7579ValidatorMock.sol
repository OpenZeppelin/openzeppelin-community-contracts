// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC7579Validator} from "../../../account/modules/ERC7579Validator.sol";

abstract contract ERC7579ValidatorMock is ERC7579Validator {
    function onInstall(bytes calldata data) public virtual {}

    function onUninstall(bytes calldata) public virtual {}

    /// WARNING: This validator returns true for all signatures starting in `0x01` for testing purposes.
    function _isValidSignatureWithSender(
        address /* sender */,
        bytes32 /* hash */,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        uint256 offset = signature.length;
        return bytes1(signature[offset - 1:offset]) == bytes1(0x01);
    }
}
