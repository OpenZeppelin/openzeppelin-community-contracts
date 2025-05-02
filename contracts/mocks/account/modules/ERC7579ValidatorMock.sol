// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ERC7579Validator} from "../../../account/modules/ERC7579Validator.sol";
import {ERC7579Module} from "../../../account/modules/ERC7579Module.sol";
import {IERC7579Module} from "@openzeppelin/contracts/interfaces/draft-IERC7579.sol";

abstract contract ERC7579ValidatorMock is ERC7579Validator {
    mapping(address sender => address signer) private _associatedSigners;

    function onInstall(bytes calldata data) public virtual override(ERC7579Module, IERC7579Module) {
        _associatedSigners[msg.sender] = address(bytes20(data[0:20]));
        super.onInstall(data);
    }

    function onUninstall(bytes calldata data) public virtual override(ERC7579Module, IERC7579Module) {
        delete _associatedSigners[msg.sender];
        super.onUninstall(data);
    }

    /// @dev Internal version of {isValidSignatureWithSender} to be implemented by derived contracts.
    function _isValidSignatureWithSender(
        address /* sender */,
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override returns (bool) {
        return SignatureChecker.isValidSignatureNow(_associatedSigners[msg.sender], hash, signature);
    }
}
