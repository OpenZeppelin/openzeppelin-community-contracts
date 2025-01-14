// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../account/Account.sol";
import {AbstractSigner, SignerECDSA} from "../../utils/cryptography/SignerECDSA.sol";

abstract contract AccountECDSAMock is Account, SignerECDSA {
    constructor(address signerAddr) {
        _initializeSigner(signerAddr);
    }

    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(AbstractSigner, SignerECDSA) returns (bool) {
        return super._rawSignatureValidation(hash, signature);
    }
}
