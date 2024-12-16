// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../account/draft-Account.sol";
import {AccountRSA} from "../../account/extensions/draft-AccountRSA.sol";

abstract contract AccountRSAMock is Account, AccountRSA {
    constructor(bytes memory e, bytes memory n) {
        _initializeSigner(e, n);
    }

    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(Account, AccountRSA) returns (bool) {
        return super._rawSignatureValidation(hash, signature);
    }
}
