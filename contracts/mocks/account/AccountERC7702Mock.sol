// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Account} from "../../account/Account.sol";
import {AbstractSigner, SignerERC7702} from "../../utils/cryptography/SignerERC7702.sol";

abstract contract AccountERC7702Mock is Account, SignerERC7702 {
    function _rawSignatureValidation(
        bytes32 hash,
        bytes calldata signature
    ) internal view virtual override(AbstractSigner, SignerERC7702) returns (bool) {
        return super._rawSignatureValidation(hash, signature);
    }
}
