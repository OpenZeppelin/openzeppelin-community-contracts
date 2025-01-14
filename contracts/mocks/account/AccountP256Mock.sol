// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../account/Account.sol";
import {SignerP256, AbstractSigner} from "../../utils/cryptography/SignerP256.sol";

abstract contract AccountP256Mock is Account, SignerP256 {
    constructor(bytes32 qx, bytes32 qy) {
        _initializeSigner(qx, qy);
    }

    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(AbstractSigner, SignerP256) returns (bool) {
        return super._rawSignatureValidation(hash, signature);
    }
}
