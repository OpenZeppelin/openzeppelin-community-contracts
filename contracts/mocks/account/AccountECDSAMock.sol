// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../account/draft-Account.sol";
import {AccountECDSA} from "../../account/extensions/draft-AccountECDSA.sol";

abstract contract AccountECDSAMock is Account, AccountECDSA {
    constructor(address signerAddr) {
        _initializeSigner(signerAddr);
    }

    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(Account, AccountECDSA) returns (bool) {
        return super._rawSignatureValidation(hash, signature);
    }
}
