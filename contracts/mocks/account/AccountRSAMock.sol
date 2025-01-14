// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../account/Account.sol";
import {AbstractSigner, SignerRSA} from "../../utils/cryptography/SignerRSA.sol";

abstract contract AccountRSAMock is Account, SignerRSA {
    constructor(bytes memory e, bytes memory n) {
        _initializeSigner(e, n);
    }

    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(AbstractSigner, SignerRSA) returns (bool) {
        return super._rawSignatureValidation(hash, signature);
    }
}
