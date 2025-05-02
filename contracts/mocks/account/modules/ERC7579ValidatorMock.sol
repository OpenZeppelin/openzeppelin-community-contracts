// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ERC7579Validator} from "../../../account/modules/ERC7579Validator.sol";
import {IERC7579Module} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

abstract contract ERC7579ValidatorMock is ERC7579Validator {
    mapping(address sender => address signer) private _associatedSigners;

    /// @inheritdoc ERC7579Validator
    function onInstall(bytes calldata data) public virtual override {
        _associatedSigners[msg.sender] = address(bytes20(data[0:20]));
    }

    /// @inheritdoc ERC7579Validator
    function onUninstall(bytes calldata) public virtual override {
        delete _associatedSigners[msg.sender];
    }

    /// @dev Validates the ECDSA signature of the sender against the associated signer.
    function _isValidSignatureWithSender(
        address /* sender */,
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        return SignatureChecker.isValidSignatureNow(_associatedSigners[msg.sender], hash, signature);
    }
}
