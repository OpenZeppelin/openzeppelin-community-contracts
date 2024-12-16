// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../account/draft-Account.sol";
import {AccountP256} from "../../account/extensions/draft-AccountP256.sol";

abstract contract AccountP256Mock is Account, AccountP256 {
    constructor(bytes32 qx, bytes32 qy) {
        _initializeSigner(qx, qy);
    }

    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(Account, AccountP256) returns (bool) {
        return super._rawSignatureValidation(hash, signature);
    }
}
